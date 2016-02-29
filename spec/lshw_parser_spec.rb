require 'genesis_collector/lshw_parser'

RSpec.describe GenesisCollector::LshwParser do
  let(:disks)   { fixture('disks.xml') }
  let(:cpu)     { fixture('cpu.xml') }
  let(:mem)     { fixture('mem.xml') }
  let(:network) { fixture('lshw_network_interfaces.xml') }

  context 'disks' do
    it 'should parse properly' do
      lshw = GenesisCollector::LshwParser.new(disks)
      expect(lshw.disks[0][:serial_number]).to eq('1')
      expect(lshw.disks[0][:size]).to eq(998999326720)
      expect(lshw.disks[0][:kind]).to eq('scsi')
      expect(lshw.disks[0][:product]).to eq('SMC2208')
      expect(lshw.disks[0][:vendor_name]).to eq(nil)
      expect(lshw.disks[2][:description]).to eq('DVD-RAM writer')
    end

    it 'should parse disk nodes with no product element' do
      lshw = GenesisCollector::LshwParser.new(disks)
      expect(lshw.disks[3][:description]).to eq('SCSI Disk (no product element)')
    end
  end

  context 'cpu' do
    it 'should parse properly' do
      lshw = GenesisCollector::LshwParser.new(cpu)
      expect(lshw.cpus[0][:threads]).to eq(16)
      expect(lshw.cpus[0][:cores]).to eq(8)
    end

    it 'should handle empty CPU socket' do
      lshw = GenesisCollector::LshwParser.new(cpu)
      expect(lshw.cpus[2][:description]).to eq('CPU [empty]')
      expect(lshw.cpus[2][:physid]).to eq(2)
    end
  end

  context 'memory' do
    it 'should parse properly' do
      lshw = GenesisCollector::LshwParser.new(mem)
      expect(lshw.memories[0][:bank]).to eq(0)
      expect(lshw.memories[1][:size]).to eq(8589934592)
    end

    it 'should not include cpu caches' do
      lshw = GenesisCollector::LshwParser.new(mem)
      expect(lshw.memories[0][:bank]).to_not eq(6)
    end

    it 'should handle empty memory slots' do
      lshw = GenesisCollector::LshwParser.new(mem)
      expect(lshw.memories[2][:description]).to eq('DIMM DDR3 Synchronous [empty]')
    end

    it 'should handle memory info with no slot info' do
      lshw = GenesisCollector::LshwParser.new(mem)
      expect(lshw.memories[3][:description]).to eq('Entry with no slot info')
    end
  end

  context 'network' do
    it 'should parse interfaces properly' do
      lshw = GenesisCollector::LshwParser.new(network)
      expect(lshw.network_interfaces[0][:name]).to eq('eth0')
      expect(lshw.network_interfaces[0][:description]).to eq('Ethernet interface')
      expect(lshw.network_interfaces[0][:mac_address]).to eq('00:25:90:89:8e:e0')
      expect(lshw.network_interfaces[0][:product]).to eq('Ethernet Controller 10 Gigabit X540-AT2')
      expect(lshw.network_interfaces[0][:vendor_name]).to eq('Intel Corporation')
      expect(lshw.network_interfaces[0][:driver]).to eq('ixgbe')
      expect(lshw.network_interfaces[0][:driver_version]).to eq('3.11.33-k')
      expect(lshw.network_interfaces[0][:duplex]).to eq('full')
      expect(lshw.network_interfaces[0][:link_type]).to eq('twisted pair')
    end

    it 'should parse bond0 interfaces properly' do
      lshw = GenesisCollector::LshwParser.new(network)
      expect(lshw.network_interfaces[1][:name]).to eq('bond0')
      expect(lshw.network_interfaces[1][:description]).to eq('Ethernet interface')
    end
  end
end
