require 'genesis_collector/lshw_parser'

RSpec.describe GenesisCollector::LshwParser do
  let(:mem)     { fixture('mem.xml') }

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

end
