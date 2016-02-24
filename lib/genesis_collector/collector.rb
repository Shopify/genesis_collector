require 'json'
require 'resolv'
require 'socket'
require 'genesis_collector/simple_http'
require 'English'

module GenesisCollector
  class Collector
    attr_reader :payload

    def initialize(config = {})
      @chef_node = config.delete(:chef_node)
      @config = config
      @payload = {}
    end

    def collect!
      @sku = get_sku
      collect_basic_data
      collect_chef
      collect_ipmi
      collect_interface_ips
      @payload
    end

    def submit!
      fail 'Must collect data first!' unless @payload
      http = SimpleHTTP.new(host, 'Authorization' => "Token token=\"#{apikey}\"",
                                  'Content-Type'  => 'application/json')
      http.patch("/api/devices/#{@sku}", @payload)
    end

    def collect_interface_ips
      # I'm assuming that physical means it is of the form "ethX", so biosdevnames break this assumption.
      interfaces = {}
      Socket.getifaddrs.each do |ifaddr|
        next if !ifaddr.name.start_with?('eth', 'bond') || !ifaddr.addr.ipv4?
        interfaces[ifaddr.name] ||= []
        interfaces[ifaddr.name] << { address:  ifaddr.addr.ip_address,
                                     netmask:  ifaddr.netmask.ip_address
                                   }
      end
      @payload[:interfaces] = interfaces
    end

    def collect_basic_data
      @payload = {
        type: 'Server',
        hostname: get_hostname,
        os: {
          distribution: get_distribution,
          release: get_release,
          codename: get_codename,
          description: get_description
        },
        product: read_dmi('system-product-name'),
        vendor: read_dmi('system-manufacturer'),
        properties: {
          'SYSTEM_SERIAL_NUMBER' => read_dmi('system-serial-number'),
          'BASEBOARD_VENDOR' => read_dmi('baseboard-manufacturer'),
          'BASEBOARD_PRODUCT_NAME' => read_dmi('baseboard-product-name'),
          'BASEBOARD_SERIAL_NUMBER' => read_dmi('baseboard-serial-number'),
          'CHASSIS_VENDOR' => read_dmi('chassis-manufacturer'),
          'CHASSIS_SERIAL_NUMBER' => read_dmi('chassis-serial-number')
        }
      }
    end

    # def collect_lldp
    #   format = 'xml'
    #   data = shellout_with_timeout('lldpctl -f xml')
    #   if data.empty? or data.index('xml').nil?
    #     data = shellout_with_timeout('lldpctl -f keyvalue')
    #     format = 'kvp'
    #   end
    #   if data.empty?
    #     format = 'flat'
    #     data = shellout_with_timeout('lldpctl')
    #   end
    #
    #   @api.submit_lldp({ output: format, payload: data })
    # end

    # def collect_lshw
    #   payload = shellout_with_timeout('lshw -xml', 40).strip
    #   @api.submit_lshw({ output: 'xml', payload: payload })
    # end

    def collect_ipmi
      @payload[:ipmi] = {
        address: read_ipmi_attribute('IP Address'),
        netmask: read_ipmi_attribute('Subnet Mask'),
        mac: read_ipmi_attribute('MAC Address'),
        gateway: read_ipmi_attribute('Default Gateway IP')
      }
    end

    def collect_chef
      @payload[:chef] = {
        environment: get_chef_environment,
        roles: (@chef_node.respond_to?(:[]) ? @chef_node['roles'] : []),
        run_list: (@chef_node.respond_to?(:[]) ? @chef_node['run_list'] : ''),
        tags: get_chef_tags
      }
    end

    private

    def shellout_with_timeout(command, timeout = 2)
      response = `timeout #{timeout} #{command}`
      unless $CHILD_STATUS.success?
        puts "Call to #{command} timed out after #{timeout} seconds"
        return ''
      end
      response
    end

    def get_distribution
      read_lsb_key('DISTRIB_ID').downcase
    end

    def get_release
      read_lsb_key('DISTRIB_RELEASE').downcase
    end

    def get_codename
      read_lsb_key('DISTRIB_CODENAME').downcase
    end

    def get_description
      read_lsb_key('DISTRIB_DESCRIPTION').downcase
    end

    def get_hostname
      Socket.gethostname
    end

    def get_chef_environment
      env = nil
      env = File.read('/etc/chef/current_environment').gsub(/\s+/, '') if File.exist? '/etc/chef/current_environment'
      env || 'unknown'
    end

    def get_chef_tags
      node_show_output = shellout_with_timeout('knife node show `hostname` -c /etc/chef/client.rb')
      node_show_output.match(/Tags:(.*)/)[0].delete(' ').gsub('Tags:', '').split(',')
    rescue
      []
    end

    def read_lsb_key(key)
      @lsb_data ||= File.read('/etc/lsb-release')
      @lsb_data.match(/#{key}=([\S\W]+)\n/)[1] || 'unknown'
    end

    def subnetify(addr)
      return nil unless addr
      addr.split('.').take(3).join('.')
    end

    def read_ipmi_attribute(key)
      data = shellout_with_timeout('ipmitool lan print')
      data.match(/#{key}\s*:\s*(\S+)$/)[1] || 'unknown'
    end

    def read_ipmi_fru(key)
      data = shellout_with_timeout('ipmitool fru')
      data.match(/#{key}\s*:\s*(\S+)$/)[1] || 'unknown'
    end

    def get_sku
      vendor = nil
      serial = nil
      vendor ||= read_dmi 'baseboard-manufacturer'
      serial ||= read_dmi 'baseboard-serial-number'
      serial = nil if serial == '0123456789'

      vendor ||= read_dmi 'system-manufacturer'
      serial ||= read_dmi 'system-serial-number'
      serial = nil if serial == '0123456789'

      serial ||= read_ipmi_fru('Board Serial')

      vendor ||= 'Unknown'
      manufacturer = case vendor
                     when 'DellInc'
                       'DEL'
                     when 'Supermicro'
                       'SPM'
                     else
                       'UKN'
      end
      "#{manufacturer}-#{serial}"
    end

    def read_dmi(key)
      value = shellout_with_timeout("dmidecode -s #{key}").gsub(/\s+|\./, '')
      value.empty? ? nil : value
    end
  end
end
