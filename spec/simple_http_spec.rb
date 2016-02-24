require 'genesis_collector/simple_http'

RSpec.describe GenesisCollector::SimpleHTTP do
  describe '#initialize' do
    it 'requires host' do
      expect {
        GenesisCollector::SimpleHTTP.new
      }.to raise_error(ArgumentError)
    end
    it 'only requires host to initialize' do
      expect {
        GenesisCollector::SimpleHTTP.new('http://example.com')
      }.not_to raise_error
    end
  end

  describe '#patch' do
    context 'with no default headers' do
      let(:http) { GenesisCollector::SimpleHTTP.new('http://example.com') }
      context 'with no new headers' do
        let(:uri) { 'http://example.com/1' }
        before { stub_request(:patch, uri).with(headers: {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'User-Agent'=>'GenesisCollector/0.1.0' }).to_return(status: 200, body: '{foo: "bar"}') }
        let!(:response) { http.patch('/1', {}, {}) }
        it 'sends the correct http request' do
        end
        it 'returns status code 200' do
          expect(response.code).to eq('200')
        end
        it 'returns response body' do
          expect(response.body).to eq('{foo: "bar"}')
        end
      end
    end
  end
end
