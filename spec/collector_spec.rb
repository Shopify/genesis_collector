require 'genesis_collector/collector'

RSpec.describe GenesisCollector::Collector do
  let(:config) { {} }
  let(:collector) { GenesisCollector::Collector.new(config) }

  describe 'error handling' do
    before do
      allow_any_instance_of(GenesisCollector::Collector).to \
        receive(:get_sku).and_return('ABC123')
    end
    context 'with error_handler' do
      before do
        config[:error_handler] = ->(a) { raise "TEST ERROR HANDLED: #{a.message}" }
      end
      it 'should handle errors' do
        expect { collector.collect! }.to raise_error(RuntimeError, /TEST ERROR HANDLED/)
      end
    end
    context 'without error_handler' do
      it 'should hide errors' do
        collector.collect!
      end
    end
  end

  describe '#safely' do
    it 'should catch errors' do
      collector.send(:safely) { raise "foo" }
    end
  end

  describe '#get_sku' do
    before do
      stub_dmi('baseboard-manufacturer', 'Supermicro')
      stub_dmi('baseboard-serial-number', '34524623454')
    end
    it 'should get sku' do
      expect(collector.send(:get_sku)).to eq('SPM-34524623454')
    end
    context 'broken bios' do
      before do
        stub_dmi('baseboard-serial-number', '0123456789')
        stub_dmi('system-serial-number', '0123456789')
        stub_shellout('ipmitool fru', fixture('ipmitool_fru'))
      end
      it 'should get sku with real serial number' do
        expect(collector.send(:get_sku)).to eq('SPM-ZM234234235234')
      end
    end
  end

  describe '#read_dmi' do
    context 'with broken dmidecode' do
      before do
        stub_dmi('baseboard-manufacturer', "# SMBIOS implementations newer than version 2.8 are not\n# fully supported by this version of dmidecode.\nSupermicro")
        stub_dmi('baseboard-serial-number', "# SMBIOS implementations newer than version 2.8 are not\n# fully supported by this version of dmidecode.\nHM15CS331193")
      end
      it 'should get real value' do
        expect(collector.send(:read_dmi, 'baseboard-manufacturer')).to eq('Supermicro')
        expect(collector.send(:read_dmi, 'baseboard-serial-number')).to eq('HM15CS331193')
      end
    end
  end

  describe '#read_node_position' do
    context 'on old without ipmicfg' do
      before { stub_shellout('sudo ipmicfg -tp nodeid', '') }
      it 'returns nil' do
        expect(collector.send(:read_node_position)).to eq(nil)
      end
    end
    context 'with ipmicfg tool available' do
      before { stub_shellout('sudo ipmicfg -tp nodeid', 'B') }
      it 'returns node id' do
        expect(collector.send(:read_node_position)).to eq('B')
      end
    end
    context 'on old node' do
      before { stub_shellout('sudo ipmicfg -tp nodeid', 'Not TwinPro') }
      it 'returns nil' do
        expect(collector.send(:read_node_position)).to eq(nil)
      end
    end
  end

  describe '#get_last_boot_time' do
    before { stub_shellout('date -d "`cut -f1 -d. /proc/uptime` seconds ago" -u', 'Mon Aug 31 09:56:15 UTC 2015') }
    it 'returns proper timestamp' do
      expect(collector.send(:get_last_boot_time)).to eq('2015-08-31T09:56:15Z')
    end
  end

  describe '#collect_basic_data' do
    before do
      allow(Socket).to receive(:gethostname).and_return('test1234')
      allow(Socket).to receive(:gethostbyname).and_return(['test1234.example.com', ['test1234'], 2, "\xAC\x18@1"])
      stub_file_content('/etc/lsb-release', fixture('lsb-release'))
      stub_dmi('system-manufacturer', 'Acme Inc')
      stub_dmi('baseboard-manufacturer', 'Super Acme Inc')
      stub_dmi('chassis-manufacturer', 'Acme Chassis Inc')
      stub_shellout('date -d "`cut -f1 -d. /proc/uptime` seconds ago" -u', 'Mon Aug 31 09:56:15 UTC 2015')
    end
    context 'with working bios' do
      before do
        stub_dmi('system-product-name', 'ABC123+')
        stub_dmi('system-serial-number', '1234567891234')
        stub_dmi('baseboard-product-name', 'ABC456B+')
        stub_dmi('baseboard-serial-number', '34524623454')
        stub_dmi('chassis-serial-number', '2376482364')
        collector.collect_basic_data
      end
      let(:payload) { collector.payload }
      it 'should get hostname' do
        expect(payload[:hostname]).to eq('test1234')
      end
      it 'should get fqdn' do
        expect(payload[:fqdn]).to eq('test1234.example.com')
      end
      context 'with hostname == fqdn' do
        before { allow(Socket).to receive(:gethostname).and_return('test1234.example.com') }
        it 'hostname equals fqdn' do
          collector.collect_basic_data
          expect(payload[:hostname]).to eq('test1234.example.com')
          expect(payload[:fqdn]).to eq('test1234.example.com')
        end
      end
      context 'with DNS not working' do
        before { allow(Socket).to receive(:gethostbyname).and_raise(SocketError) }
        it 'returns nil for fqdn' do
          collector.collect_basic_data
          expect(payload[:fqdn]).to eq(nil)
        end
      end
      it 'should get os attributes' do
        expect(payload[:os][:distribution]).to eq('Ubuntu')
        expect(payload[:os][:release]).to eq('14.04')
        expect(payload[:os][:codename]).to eq('trusty')
        expect(payload[:os][:description]).to eq('Ubuntu 14.04.2 LTS')
      end
      it 'should get product name' do
        expect(payload[:product]).to eq('ABC123+')
      end
      it 'should get vendor name' do
        expect(payload[:vendor]).to eq('Acme Inc')
      end
      it 'should get extra properties' do
        expect(payload[:properties]['SYSTEM_SERIAL_NUMBER']).to eq('1234567891234')
        expect(payload[:properties]['BASEBOARD_VENDOR']).to eq('Super Acme Inc')
        expect(payload[:properties]['BASEBOARD_PRODUCT_NAME']).to eq('ABC456B+')
        expect(payload[:properties]['BASEBOARD_SERIAL_NUMBER']).to eq('34524623454')
        expect(payload[:properties]['CHASSIS_VENDOR']).to eq('Acme Chassis Inc')
        expect(payload[:properties]['CHASSIS_SERIAL_NUMBER']).to eq('2376482364')
      end
    end

    context 'when supermicro' do
      before do
        stub_shellout('sudo ipmicfg -tp nodeid', 'B')
        stub_dmi('system-manufacturer', 'Supermicro')
        stub_dmi('baseboard-manufacturer', 'Supermicro')
        stub_dmi('chassis-manufacturer', 'Supermicro')
        stub_dmi('system-product-name', 'ABC123+')
        stub_dmi('system-serial-number', '1234567891234')
        stub_dmi('baseboard-product-name', 'ABC456B+')
        stub_dmi('baseboard-serial-number', '34524623454')
        stub_dmi('chassis-serial-number', '2376482364')
        collector.collect_basic_data
      end
      let(:payload) { collector.payload }

      it 'should send position' do
        expect(payload[:properties]['NODE_POSITION_IN_CHASSIS']).to eq('B')
      end
    end

    context 'with broken bios' do
      before do
        allow(Socket).to receive(:gethostname).and_return('test1234.example.com')
        stub_file_content('/etc/lsb-release', fixture('lsb-release'))
        stub_dmi('system-product-name', 'X9DRW')
        stub_dmi('system-serial-number', '0123456789')
        stub_dmi('baseboard-product-name', 'X9DRW')
        stub_dmi('baseboard-serial-number', '0123456789')
        stub_dmi('chassis-serial-number', '0123456789')
        stub_shellout('ipmitool fru', fixture('ipmitool_fru'))
        collector.collect_basic_data
      end
      let(:payload) { collector.payload }
      it 'should get correct extra properties' do
        expect(payload[:product]).to eq('SYS-2028DR-HTTR')
        expect(payload[:properties]['SYSTEM_SERIAL_NUMBER']).to eq('S23425234234324')
        expect(payload[:properties]['BASEBOARD_PRODUCT_NAME']).to eq('X9DRT-PT')
        expect(payload[:properties]['BASEBOARD_SERIAL_NUMBER']).to eq('ZM234234235234')
        expect(payload[:properties]['CHASSIS_SERIAL_NUMBER']).to eq('CA1351A238463')
      end
    end
  end

  describe '#collect_chef' do
    let(:payload) { collector.collect_chef; collector.payload }
    context 'with chef node' do
      let(:config) { { chef_node: double('Chef::Node', roles: ['role-one', 'role-two'], run_list: 'role[location--lax], role[app--genesis--server]', tags: ['tagone', 'secondary'], chef_environment: 'some-branch', ohai_time: 1456846679.5199523) } }
      it 'should get roles' do
        expect(payload[:chef][:roles]).to eq(['role-one', 'role-two'])
      end
      it 'should get run list' do
        expect(payload[:chef][:run_list]).to eq('role[location--lax], role[app--genesis--server]')
      end
      it 'should get tags' do
        expect(payload[:chef][:tags]).to eq(['tagone', 'secondary'])
      end
      it 'should get environment' do
        expect(payload[:chef][:environment]).to eq('some-branch')
      end
      it 'should get last run' do
        expect(payload[:chef][:last_run]).to eq('2016-03-01T15:37:59Z')
      end
    end
    context 'without chef node when knife works' do
      before { stub_shellout('knife node show `hostname` -c /etc/chef/client.rb -a ohai_time -a run_list -a tags -a environment -a roles --format json', fixture('knife_node_show')) }
      it 'should get roles' do
        expect(payload[:chef][:roles]).to eq(['role-three', 'role-four'])
      end
      it 'should get run list' do
        expect(payload[:chef][:run_list]).to eq('role[location--pdx], role[app--genesis--server]')
      end
      it 'should get tags' do
        expect(payload[:chef][:tags]).to eq(['tagone', 'primary'])
      end
      it 'should get environment' do
        expect(payload[:chef][:environment]).to eq('some-other-branch')
      end
      it 'should get last run' do
        expect(payload[:chef][:last_run]).to eq('2016-03-01T15:08:17Z')
      end
    end
    context 'without chef node and when knife fails' do
      before { stub_shellout('knife node show `hostname` -c /etc/chef/client.rb -a ohai_time -a run_list -a tags -a environment -a roles --format json', nil) }
      it 'should return nil' do
        expect(payload[:chef]).to eq(nil)
      end
    end
  end

  describe '#collect_ipmi' do
    before { stub_shellout_with_timeout('ipmitool lan print', 10, fixture('ipmitool_lan_print')) }
    let(:payload) { collector.collect_ipmi; collector.payload }
    it 'should get address' do
      expect(payload[:ipmi][:address]).to eq('1.2.1.2')
    end
    it 'should get netmask' do
      expect(payload[:ipmi][:netmask]).to eq('255.255.0.0')
    end
    it 'should get mac' do
      expect(payload[:ipmi][:mac]).to eq('0c:ca:ca:03:dc:23')
    end
    it 'should get gateway' do
      expect(payload[:ipmi][:gateway]).to eq('1.2.0.1')
    end
  end

  describe '#collect_network_interfaces' do
    before do
      allow(Socket).to receive(:getifaddrs).and_return([
        instance_double('Socket::Ifaddr', name: 'lo'),
        instance_double('Socket::Ifaddr', name: 'eth0', addr: instance_double('Socket::Addrinfo', ip_address: '1.2.3.4', ip?: true), netmask: instance_double('Socket::Addrinfo', ip_address: '255.255.255.0')),
        instance_double('Socket::Ifaddr', name: 'eth0', addr: instance_double('Socket::Addrinfo', ip_address: 'fd3e:efc1:a0e3:703b::2%eth0', ip?: true), netmask: instance_double('Socket::Addrinfo', ip_address: 'ffff:ffff:ffff:ffff::')),
        instance_double('Socket::Ifaddr', name: 'eth1', addr: instance_double('Socket::Addrinfo', ip_address: '1.2.3.5', ip?: true), netmask: instance_double('Socket::Addrinfo', ip_address: '255.255.0.0')),
        instance_double('Socket::Ifaddr', name: 'eth1', addr: instance_double('Socket::Addrinfo', ip_address: '1.2.3.6', ip?: true), netmask: instance_double('Socket::Addrinfo', ip_address: '255.0.0.0')),
        instance_double('Socket::Ifaddr', name: 'docker0', addr: instance_double('Socket::Addrinfo', ip_address: '1.2.3.7', ip?: true), netmask: instance_double('Socket::Addrinfo', ip_address: '255.255.0.0')),
        instance_double('Socket::Ifaddr', name: 'something0', addr: nil)
      ])
      stub_file_content('/sys/class/net/eth0/address', "0c:ca:ca:03:12:34\n")
      stub_file_content('/sys/class/net/eth1/address', "0c:ca:ca:03:12:35")
      stub_file_content('/sys/class/net/eth0/operstate', "up\n")
      stub_file_content('/sys/class/net/eth1/operstate', 'up')
      stub_file_content('/sys/class/net/eth0/carrier', "1\n")
      stub_file_content('/sys/class/net/eth1/carrier', '1')
      stub_file_content('/sys/class/net/eth0/speed', "10000\n")
      stub_file_content('/sys/class/net/eth1/speed', "1000\n")
      stub_file_exists('/sys/class/net/eth0/bonding_slave/perm_hwaddr', exists: false)
      stub_file_exists('/sys/class/net/eth1/bonding_slave/perm_hwaddr', exists: false)
      stub_file_content('/sys/class/net/eth0/duplex', "full\n")
      stub_file_content('/sys/class/net/eth1/duplex', "half\n")
      stub_shellout('ethtool --driver eth0', fixture('ethtool_driver1'))
      stub_shellout('ethtool --driver eth1', fixture('ethtool_driver2'))
      stub_shellout('lldpctl -f keyvalue', fixture('lldp'))
      stub_file_exists('/sys/class/net/eth0/device')
      stub_file_exists('/sys/class/net/eth1/device')
      stub_file_exists('/sys/class/net/bond0/device', exists: false)
      allow(File).to receive(:readlink).with('/sys/class/net/eth0/device').and_return('../../../0000:06:00.0')
      allow(File).to receive(:readlink).with('/sys/class/net/eth1/device').and_return('../../../0000:06:00.1')
      stub_shellout('lspci -v -mm -s 0000:06:00.0', fixture('lspci'))
      stub_shellout('lspci -v -mm -s 0000:06:00.1', fixture('lspci'))
    end
    let(:payload) { collector.collect_network_interfaces; collector.payload }
    it 'should get 2 interfaces' do
      expect(payload[:network_interfaces].count).to eq(2)
    end
    it 'should get names' do
      expect(payload[:network_interfaces][0][:name]).to eq('eth0')
      expect(payload[:network_interfaces][1][:name]).to eq('eth1')
    end
    it 'should get the status' do
      expect(payload[:network_interfaces][0][:status]).to eq('up')
      expect(payload[:network_interfaces][1][:status]).to eq('up')
    end
    it 'should get product' do
      expect(payload[:network_interfaces][0][:product]).to eq('Ethernet Controller 10-Gigabit X540-AT2')
      expect(payload[:network_interfaces][1][:product]).to eq('Ethernet Controller 10-Gigabit X540-AT2')
    end
    it 'should get vendor name' do
      expect(payload[:network_interfaces][0][:vendor_name]).to eq('Intel Corporation')
      expect(payload[:network_interfaces][1][:vendor_name]).to eq('Intel Corporation')
    end
    it 'should get mac address' do
      expect(payload[:network_interfaces][0][:mac_address]).to eq('0c:ca:ca:03:12:34')
      expect(payload[:network_interfaces][1][:mac_address]).to eq('0c:ca:ca:03:12:35')
    end
    it 'should get speed' do
      expect(payload[:network_interfaces][0][:speed]).to eq('10000000000')
      expect(payload[:network_interfaces][1][:speed]).to eq('1000000000')
    end
    it 'should get addresses and netmasks' do
      expect(payload[:network_interfaces][0][:addresses].count).to eq(2)
      expect(payload[:network_interfaces][0][:addresses][0][:address]).to eq('1.2.3.4')
      expect(payload[:network_interfaces][0][:addresses][0][:netmask]).to eq('255.255.255.0')
      expect(payload[:network_interfaces][0][:addresses][1][:address]).to eq('fd3e:efc1:a0e3:703b::2')
      expect(payload[:network_interfaces][0][:addresses][1][:netmask]).to eq('ffff:ffff:ffff:ffff::')
      expect(payload[:network_interfaces][1][:addresses].count).to eq(2)
      expect(payload[:network_interfaces][1][:addresses][0][:address]).to eq('1.2.3.5')
      expect(payload[:network_interfaces][1][:addresses][1][:address]).to eq('1.2.3.6')
      expect(payload[:network_interfaces][1][:addresses][0][:netmask]).to eq('255.255.0.0')
      expect(payload[:network_interfaces][1][:addresses][1][:netmask]).to eq('255.0.0.0')
    end
    context 'with a down interface' do
      before do
        stub_file_content('/sys/class/net/eth1/operstate', 'down')
      end
      it 'should get the status' do
        expect(payload[:network_interfaces][1][:status]).to eq('down')
      end
      it 'speed should be nil' do
        expect(payload[:network_interfaces][1][:speed]).to eq(nil)
      end
      it 'duplex should be nil' do
        expect(payload[:network_interfaces][1][:duplex]).to eq(nil)
      end
    end
    context 'with bonded interfaces' do
      before do
        allow(Socket).to receive(:getifaddrs).and_return([
          instance_double('Socket::Ifaddr', name: 'eth0', addr: instance_double('Socket::Addrinfo', ip?: false)),
          instance_double('Socket::Ifaddr', name: 'eth1', addr: instance_double('Socket::Addrinfo', ip?: false)),
          instance_double('Socket::Ifaddr', name: 'bond0', addr: instance_double('Socket::Addrinfo', ip_address: '1.2.3.4', ip?: true), netmask: instance_double('Socket::Addrinfo', ip_address: '255.0.0.0'))
        ])
        stub_file_content('/sys/class/net/eth0/address', '0c:ca:ca:03:12:34')
        stub_file_content('/sys/class/net/eth1/address', '0c:ca:ca:03:12:34')
        stub_file_content('/sys/class/net/eth0/bonding_slave/perm_hwaddr', '0c:ca:ca:03:12:34')
        stub_file_content('/sys/class/net/eth1/bonding_slave/perm_hwaddr', '0c:ca:ca:03:12:35')
        stub_file_content('/sys/class/net/bond0/address', '0c:ca:ca:03:12:34')
        stub_file_content('/sys/class/net/bond0/operstate', 'up')
        stub_file_content('/sys/class/net/bond0/carrier', '1')
        stub_file_content('/sys/class/net/bond0/speed', '10000')
        stub_file_content('/sys/class/net/bond0/duplex', 'full')
        stub_shellout('ethtool --driver bond0', fixture('ethtool_driver_bond'))
      end
      it 'should get the real permanent mac address' do
        expect(payload[:network_interfaces][0][:mac_address]).to eq('0c:ca:ca:03:12:34')
        expect(payload[:network_interfaces][1][:mac_address]).to eq('0c:ca:ca:03:12:35')
      end
      it 'should still include ethX devices' do
        expect(payload[:network_interfaces][0][:addresses].count).to eq(0)
        expect(payload[:network_interfaces][1][:addresses].count).to eq(0)
        expect(payload[:network_interfaces][2][:addresses].count).to eq(1)
        expect(payload[:network_interfaces][2][:addresses][0][:address]).to eq('1.2.3.4')
      end
      it 'should get driver' do
        expect(payload[:network_interfaces][2][:driver]).to eq('bonding')
      end
      it 'should get driver version' do
        expect(payload[:network_interfaces][2][:driver_version]).to eq('3.7.1')
      end
    end
    it 'should get driver' do
      expect(payload[:network_interfaces][0][:driver]).to eq('ixgbe')
      expect(payload[:network_interfaces][1][:driver]).to eq('igb')
    end
    it 'should get driver version' do
      expect(payload[:network_interfaces][0][:driver_version]).to eq('3.19.1-k')
      expect(payload[:network_interfaces][1][:driver_version]).to eq('5.2.15-k')
    end
    it 'should get duplex' do
      expect(payload[:network_interfaces][0][:duplex]).to eq('full')
      expect(payload[:network_interfaces][1][:duplex]).to eq('half')
    end
    it 'should get link type' do
      skip('Removed for now, since we are not using lshw')
      expect(payload[:network_interfaces][0][:link_type]).to eq('twisted pair')
      expect(payload[:network_interfaces][1][:link_type]).to eq(nil)
    end
    context 'network neighbors' do
      it 'gets chassis name' do
        expect(payload[:network_interfaces][0][:neighbor][:chassis_name]).to eq('lax-leaf-0601')
        expect(payload[:network_interfaces][1][:neighbor][:chassis_name]).to eq('lax-leaf-0602')
      end
      it 'gets chassis description' do
        expect(payload[:network_interfaces][0][:neighbor][:chassis_desc]).to eq('Arista Networks EOS version 4.14.9M running on an Arista Networks DCS-7050T-64')
        expect(payload[:network_interfaces][1][:neighbor][:chassis_desc]).to eq('Arista Networks EOS version 4.14.9M running on an Arista Networks DCS-7050T-64')
      end
      it 'gets chassis id type' do
        expect(payload[:network_interfaces][0][:neighbor][:chassis_id_type]).to eq('mac')
        expect(payload[:network_interfaces][1][:neighbor][:chassis_id_type]).to eq('mac')
      end
      it 'gets chassis id value' do
        expect(payload[:network_interfaces][0][:neighbor][:chassis_id_value]).to eq('00:1c:71:76:52:e5')
        expect(payload[:network_interfaces][1][:neighbor][:chassis_id_value]).to eq('00:1c:71:73:42:5f')
      end
      it 'gets port id type' do
        expect(payload[:network_interfaces][0][:neighbor][:port_id_type]).to eq('ifname')
        expect(payload[:network_interfaces][1][:neighbor][:port_id_type]).to eq('ifname')
      end
      it 'gets port id value' do
        expect(payload[:network_interfaces][0][:neighbor][:port_id_value]).to eq('Ethernet9')
        expect(payload[:network_interfaces][1][:neighbor][:port_id_value]).to eq('Ethernet29')
      end
      it 'gets port description' do
        expect(payload[:network_interfaces][0][:neighbor][:port_desc]).to eq('Not received')
        expect(payload[:network_interfaces][1][:neighbor][:port_desc]).to eq('Not received')
      end
      it 'gets vlan id' do
        expect(payload[:network_interfaces][0][:neighbor][:vlan_id]).to eq('601')
        expect(payload[:network_interfaces][1][:neighbor][:vlan_id]).to eq('602')
      end
      it 'gets vlan name' do
        expect(payload[:network_interfaces][0][:neighbor][:vlan_name]).to eq(nil)
        expect(payload[:network_interfaces][1][:neighbor][:vlan_name]).to eq(nil)
      end
    end
  end
  describe '#collect_disks' do
    before do
      allow_any_instance_of(GenesisCollector::Collector).to \
        receive(:ensure_command).with('smartctl').and_return('/usr/sbin/smartctl')
      stub_shellout('smartctl --scan', fixture('smartctl/scan'))
      stub_shellout_with_timeout('smartctl -i /dev/sda', 5, fixture('smartctl/sda'))
      stub_shellout_with_timeout('smartctl -i /dev/sdb', 5, fixture('smartctl/sdb'))
      stub_shellout_with_timeout('smartctl -i /dev/sdc', 5, fixture('smartctl/sdc'))
      stub_shellout_with_timeout('smartctl -i /dev/sdd', 5, fixture('smartctl/sdd'))
      stub_shellout_with_timeout('smartctl -i /dev/bus/0 -d megaraid,0', 5, fixture('smartctl/megaraid0'))
      stub_shellout_with_timeout('smartctl -i /dev/bus/0 -d megaraid,1', 5, fixture('smartctl/megaraid0'))
      stub_shellout_with_timeout('smartctl -i /dev/bus/0 -d megaraid,2', 5, fixture('smartctl/megaraid0'))
      stub_symlink_target('/sys/class/block/sda/device', '../../../5:0:0:0')
      stub_symlink_target('/sys/class/block/sdb/device', '../../../4:0:0:0')
      stub_symlink_target('/sys/class/block/sdc/device', '../../../3:0:0:0')
      stub_symlink_target('/sys/class/block/sdd/device', '../../../2:0:0:0')
    end
    let(:payload) { collector.collect_disks; collector.payload }
    it 'should get disks' do
      expect(payload[:disks].count).to eq(7)
    end
    it 'should get product' do
      expect(payload[:disks][0][:product]).to eq('PERC H710P')
      expect(payload[:disks][1][:product]).to eq('SAMSUNG MZ7WD960HMHP-00003')
      expect(payload[:disks][2][:product]).to eq('INTEL SSDSC2BB240G6')
      expect(payload[:disks][3][:product]).to eq('HGST HUS724040ALA640')
      expect(payload[:disks][4][:product]).to eq('Crucial_CT960M500SSD1')
    end
    it 'should get vendor' do
      expect(payload[:disks][0][:vendor_name]).to eq('DELL')
      expect(payload[:disks][1][:vendor_name]).to eq('SAMSUNG')
      expect(payload[:disks][2][:vendor_name]).to eq('INTEL')
      expect(payload[:disks][3][:vendor_name]).to eq('HGST')
      expect(payload[:disks][4][:vendor_name]).to eq('Crucial')
    end
    it 'should get dev' do
      expect(payload[:disks][0][:dev]).to eq('/dev/sda')
      expect(payload[:disks][1][:dev]).to eq('/dev/sdb')
      expect(payload[:disks][2][:dev]).to eq('/dev/sdc')
      expect(payload[:disks][3][:dev]).to eq('/dev/sdd')
      expect(payload[:disks][4][:dev]).to eq('/dev/bus/0')
    end
    it 'should get kind' do
      expect(payload[:disks][0][:kind]).to eq('SCSI device')
      expect(payload[:disks][1][:kind]).to eq('SCSI device')
      expect(payload[:disks][4][:kind]).to eq('SCSI device')
    end
    it 'should get size' do
      expect(payload[:disks][0][:size]).to eq('959656755200')
      expect(payload[:disks][1][:size]).to eq('960197124096')
      expect(payload[:disks][2][:size]).to eq('240057409536')
      expect(payload[:disks][3][:size]).to eq('4000787030016')
      expect(payload[:disks][4][:size]).to eq('960197124096')
    end
    it 'should get serial number' do
      expect(payload[:disks][0][:serial_number]).to eq('004db85d065c635f1d00e33c2320344a')
      expect(payload[:disks][1][:serial_number]).to eq('S1E4NYAG101668')
      expect(payload[:disks][2][:serial_number]).to eq('BTWA5351028H240AGN')
      expect(payload[:disks][3][:serial_number]).to eq('PN1334PCKSX7JS')
      expect(payload[:disks][4][:serial_number]).to eq('14270C89BDC6')
    end
  end
  describe '#collect_cpus' do
    before do
      stub_shellout('dmidecode --type processor --type memory', fixture('dmidecode'))
    end
    let(:payload) { collector.collect_cpus; collector.payload }
    it 'should get cpus' do
      expect(payload[:cpus].count).to eq(2)
    end
    it 'should get description' do
      expect(payload[:cpus][0][:description]).to eq('Intel(R) Xeon(R) CPU E5-2667 v2 @ 3.30GHz')
      expect(payload[:cpus][1][:description]).to eq('Intel(R) Xeon(R) CPU E5-2667 v2 @ 3.30GHz')
    end
    it 'should get cores' do
      expect(payload[:cpus][0][:cores]).to eq(8)
      expect(payload[:cpus][1][:cores]).to eq(8)
    end
    it 'should get threads' do
      expect(payload[:cpus][0][:threads]).to eq(16)
      expect(payload[:cpus][1][:threads]).to eq(16)
    end
    it 'should get speed' do
      expect(payload[:cpus][0][:speed]).to eq('3300 MHz')
      expect(payload[:cpus][1][:speed]).to eq('3300 MHz')
    end
    it 'should get vendor' do
      expect(payload[:cpus][0][:vendor_name]).to eq('Intel')
      expect(payload[:cpus][1][:vendor_name]).to eq('Intel')
    end
    it 'should get physid' do
      expect(payload[:cpus][0][:physid]).to eq('SOCKET 0')
      expect(payload[:cpus][1][:physid]).to eq('SOCKET 1')
    end
  end
  describe '#collect_memories' do
    before do
      stub_shellout('dmidecode --type processor --type memory', fixture('dmidecode'))
    end
    let(:payload) { collector.collect_memories; collector.payload }
    it 'should get memories' do
      expect(payload[:memories].count).to eq(16)
    end
    it 'should get description' do
      expect(payload[:memories][0][:description]).to eq('DIMM Registered (Buffered) 1333 MHz')
      expect(payload[:memories][1][:description]).to eq('Empty DIMM')
    end
    it 'should get size' do
      expect(payload[:memories][0][:size]).to eq(16384000000)
      expect(payload[:memories][1][:size]).to eq(0)
    end
    it 'should get bank' do
      expect(payload[:memories][0][:bank]).to eq('P0_Node0_Channel0_Dimm0')
      expect(payload[:memories][1][:bank]).to eq('P0_Node0_Channel0_Dimm1')
    end
    it 'should get slot' do
      expect(payload[:memories][0][:slot]).to eq('P1-DIMMA1')
      expect(payload[:memories][1][:slot]).to eq('P1-DIMMA2')
    end
    it 'should get vendor' do
      expect(payload[:memories][0][:vendor_name]).to eq('Samsung')
      expect(payload[:memories][1][:vendor_name]).to eq(nil)
    end
    it 'should get product' do
      expect(payload[:memories][0][:product]).to eq('M393B2G70QH0-YK0')
      expect(payload[:memories][1][:product]).to eq(nil)
    end
    it 'should get serial_number' do
      expect(payload[:memories][0][:serial_number]).to eq('1435F2EB')
      expect(payload[:memories][1][:serial_number]).to eq(nil)
    end
  end
  describe '#parse_lldp' do
    it 'should only call lldp once' do
      allow(collector).to receive(:shellout_with_timeout).and_return(fixture('lldp')).once
      collector.send(:parse_lldp)
      collector.send(:parse_lldp)
    end
  end
  describe '#get_network_neighbor' do
    it 'should only call parse_lldp once' do
      allow(collector).to receive(:shellout_with_timeout).and_return(fixture('lldp')).once
      allow(collector).to receive(:parse_lldp).and_return({}).once
      collector.send(:get_network_neighbor, 'eth0')
      collector.send(:get_network_neighbor, 'eth1')
    end
  end
end
