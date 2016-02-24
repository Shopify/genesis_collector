require 'genesis_collector/collector'

RSpec.describe GenesisCollector::Collector do
  let(:config) { {} }
  let(:collector) { GenesisCollector::Collector.new(config) }
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

  describe '#collect_basic_data' do
    before do
      allow(Socket).to receive(:gethostname).and_return('test1234.example.com')
      stub_file_content('/etc/lsb-release', fixture('lsb-release'))
      stub_dmi('system-product-name', 'ABC123+')
      stub_dmi('system-manufacturer', 'Acme Inc')
      stub_dmi('system-serial-number', '1234567891234')
      stub_dmi('baseboard-manufacturer', 'Super Acme Inc')
      stub_dmi('baseboard-product-name', 'ABC456B+')
      stub_dmi('baseboard-serial-number', '34524623454')
      stub_dmi('chassis-manufacturer', 'Acme Chassis Inc')
      stub_dmi('chassis-serial-number', '2376482364')
    end
    before { collector.collect_basic_data }
    let(:payload) { collector.payload }
    it 'should get hostname' do
      expect(payload[:hostname]).to eq('test1234.example.com')
    end
    it 'should get os attributes' do
      skip('TODO')
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

  describe '#collect_chef' do
    before { stub_shellout('knife node show `hostname` -c /etc/chef/client.rb', '') }
    let(:payload) { collector.collect_chef; collector.payload }
    context 'with chef environment set' do
      before { stub_file_content('/etc/chef/current_environment', 'some-branch') }
      it 'should get environment' do
        expect(payload[:chef][:environment]).to eq('some-branch')
      end
    end
    context 'with no chef environment set' do
      it 'should fallback to default environment string' do
        expect(payload[:chef][:environment]).to eq('unknown')
      end
    end
    context 'with chef node' do
      let(:config) { { chef_node: { 'roles' => ['role-one', 'role-two'], 'run_list' => 'role[location--lax], role[app--genesis--server]' } } }
      it 'should get roles' do
        expect(payload[:chef][:roles]).to eq(['role-one', 'role-two'])
      end
      it 'should get run list' do
        expect(payload[:chef][:run_list]).to eq('role[location--lax], role[app--genesis--server]')
      end
    end
    context 'when knife works' do
      before { stub_shellout('knife node show `hostname` -c /etc/chef/client.rb', fixture('knife_node_show')) }
      it 'should get tags' do
        expect(payload[:chef][:tags]).to eq(['tagone', 'secondary'])
      end
    end
    context 'when knife fails' do
      before { stub_shellout('knife node show `hostname` -c /etc/chef/client.rb', nil) }
      it 'should get tags' do
        expect(payload[:chef][:tags]).to eq([])
      end
    end
  end

  describe '#collect_ipmi' do
    before { stub_shellout('ipmitool lan print', fixture('ipmitool_lan_print')) }
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
end
