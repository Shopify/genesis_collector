require 'socket'

module GenesisCollector
  module NetworkInterfaces

    def collect_network_interfaces
      interfaces = {}
      Socket.getifaddrs.each do |ifaddr|
        next if ifaddr.name.start_with?('lo', 'docker', 'veth', 'cali', 'tunl')
        next if ifaddr.addr.nil?
        interfaces[ifaddr.name] ||= {}
        interfaces[ifaddr.name][:addresses] ||= []
        next unless ifaddr.addr.ip?
        interfaces[ifaddr.name][:addresses] << {
          address:  ifaddr.addr.ip_address.split('%').first,
          netmask:  ifaddr.netmask.ip_address
        }
      end
      @payload[:network_interfaces] = interfaces.reduce([]) { |memo, (k, v)| memo << v.merge(name: k) }
      @payload[:network_interfaces].each do |i|
        i[:status] = read_interface_info(i[:name], 'operstate')
        i[:mac_address] = read_mac_address(i[:name])
        if i[:status] == 'up'
          i[:speed] = get_interface_speed(i[:name])
          i[:duplex] = read_interface_info(i[:name], 'duplex')
        end
        i[:neighbor] = get_network_neighbor(i[:name])
        i.merge!(get_lspci_data(i[:name])) if File.exist?("/sys/class/net/#{i[:name]}/device")
        i.merge!(get_interface_driver(i[:name]))
      end
    end

    private

    def read_mac_address(interface)
      if !interface.start_with?('bond') && File.exist?("/sys/class/net/#{interface}/bonding_slave/perm_hwaddr")
        read_interface_info(interface, 'bonding_slave/perm_hwaddr')
      else
        read_interface_info(interface, 'address')
      end
    end

    def read_interface_info(interface, key)
      File.read("/sys/class/net/#{interface}/#{key}").strip
    end

    def get_interface_driver(interface)
      value = shellout_with_timeout("ethtool --driver #{interface}")
      { driver: value.match(/^driver: (.*)/)[1], driver_version: value.match(/^version: (.*)/)[1] }
    end

    def get_interface_speed(interface)
      return 0 if read_interface_info(interface, 'carrier') == '0'
      (read_interface_info(interface, 'speed').to_i * 1000000).to_s
    end

    def get_network_neighbor(interface_name)
      @lldp_data ||= parse_lldp
      @lldp_data[interface_name]
    end

    def parse_lldp
      @raw_lldp_output ||= shellout_with_timeout('lldpctl -f keyvalue')
      data = {}
      @raw_lldp_output.split("\n").each do |kvp|
        key, value = kvp.split('=')
        fields = key.split('.')
        name = fields[1]
        data[name] ||= { name: name }
        case fields[2..-1].join('.')
        when 'chassis.name'
          data[name][:chassis_name] = value
        when 'chassis.descr'
          data[name][:chassis_desc] = value
        when 'chassis.mac'
          data[name][:chassis_id_type] = 'mac'
          data[name][:chassis_id_value] = value
        when 'port.ifname'
          data[name][:port_id_type] = 'ifname'
          data[name][:port_id_value] = value
        when 'port.descr'
          data[name][:port_desc] = value
        when 'vlan.vlan-id'
          data[name][:vlan_id] = value
        when 'vlan'
          data[name][:vlan_name] = value
        end
      end
      data
    end

    def get_lspci_data(interface)
      slot = File.basename(File.readlink("/sys/class/net/#{interface}/device"))
      raw_data = shellout_with_timeout("lspci -v -mm -s #{slot}")
      data = {}
      raw_data.each_line do |line|
        if line.match(/^Vendor:(.*)$/)
          data[:vendor_name] = $1.strip
        end
        if line.match(/^Device:(.*)$/)
          data[:product] = $1.strip
        end
      end
      data
    end

  end
end
