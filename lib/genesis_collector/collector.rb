require 'json'
require 'resolv'
require 'socket'
require 'genesis_collector/simple_http'
require 'genesis_collector/network_interfaces'
require 'genesis_collector/chef'
require 'genesis_collector/ipmi'
require 'genesis_collector/disks'
require 'genesis_collector/dmidecode'
require 'English'

module GenesisCollector
  class Collector
    attr_reader :payload

    include GenesisCollector::NetworkInterfaces
    include GenesisCollector::Chef
    include GenesisCollector::IPMI
    include GenesisCollector::Disks
    include GenesisCollector::DmiDecode

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
      collect_network_interfaces
      collect_disks
      collect_cpus
      collect_memories
      @payload
    end

    def submit!
      fail 'Must collect data first!' unless @payload
      headers = {
        'Authorization' => "Token token=\"#{@config[:api_token]}\"",
        'Content-Type'  => 'application/json'
      }
      http = SimpleHTTP.new(@config[:endpoint], headers: headers)
      http.patch("/api/devices/#{@sku}", @payload)
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
        last_boot_at: get_last_boot_time,
        product: read_dmi('system-product-name'),
        vendor: read_dmi('system-manufacturer'),
        properties: {
          'SYSTEM_SERIAL_NUMBER' => read_dmi('system-serial-number'),
          'BASEBOARD_VENDOR' => read_dmi('baseboard-manufacturer'),
          'BASEBOARD_PRODUCT_NAME' => read_dmi('baseboard-product-name'),
          'BASEBOARD_SERIAL_NUMBER' => read_dmi('baseboard-serial-number'),
          'CHASSIS_VENDOR' => read_dmi('chassis-manufacturer'),
          'CHASSIS_SERIAL_NUMBER' => read_dmi('chassis-serial-number'),
          'NODE_POSITION_IN_CHASSIS' => read_node_position
        }
      }
      if read_dmi('system-serial-number') == nil
        @payload[:product] = read_ipmi_fru('Product Part Number')
        @payload[:properties]['SYSTEM_SERIAL_NUMBER'] = read_ipmi_fru('Product Serial')
        @payload[:properties]['BASEBOARD_PRODUCT_NAME'] = read_ipmi_fru('Board Part Number')
        @payload[:properties]['BASEBOARD_SERIAL_NUMBER'] = read_ipmi_fru('Board Serial')
        @payload[:properties]['CHASSIS_SERIAL_NUMBER'] = read_ipmi_fru('Chassis Serial')
      end
    end

    def collect_cpus
      @payload[:cpus] = get_dmi_data['processor'].map do |p|
        {
          description: p['version'],
          cores: p['core_count'].to_i,
          threads: p['thread_count'].to_i,
          speed: p['current_speed'],
          vendor_name: p['manufacturer'],
          physid: p['socket_designation']
        }
      end
    end

    def collect_memories
      @payload[:memories] = get_dmi_data['memory_device'].map do |m|
        empty = m['size'] == 'No Module Installed'
        {
          size: m['size'].to_i * 1000000,
          description: empty ? "Empty #{m['form_factor']}" : "#{m['form_factor']} #{m['type_detail']} #{m['speed']}",
          bank: m['bank_locator'],
          slot: m['locator'],
          product: empty ? nil : m['part_number'],
          vendor_name: empty ? nil : m['manufacturer']
        }
      end
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
      read_lsb_key('DISTRIB_ID')
    end

    def get_release
      read_lsb_key('DISTRIB_RELEASE')
    end

    def get_codename
      read_lsb_key('DISTRIB_CODENAME')
    end

    def get_description
      read_lsb_key('DISTRIB_DESCRIPTION')
    end

    def get_hostname
      Socket.gethostname
    end

    def get_last_boot_time
      Time.parse(shellout_with_timeout('date -d "`cut -f1 -d. /proc/uptime` seconds ago" -u')).utc.iso8601
    end

    def read_lsb_key(key)
      @lsb_data ||= File.read('/etc/lsb-release')
      @lsb_data.match(/^#{key}=["']?(.+?)["']?$/)[1] || 'unknown'
    end

    def get_sku
      vendor = nil
      serial = nil
      vendor ||= read_dmi 'baseboard-manufacturer'
      serial ||= read_dmi 'baseboard-serial-number'

      vendor ||= read_dmi 'system-manufacturer'
      serial ||= read_dmi 'system-serial-number'

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
      value = shellout_with_timeout("dmidecode -s #{key}").gsub(/^#.+$/, '').strip
      value = '' if '0123456789' == value # sometimes the firmware is broken
      value.empty? ? nil : value
    end

    def read_node_position
      value = shellout_with_timeout('sudo ipmicfg -tp nodeid').strip
      return nil unless ('A'..'Z').include?(value)
      value.empty? ? nil : value
    end
  end
end
