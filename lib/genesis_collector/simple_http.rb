require 'json'
require 'net/http'
require 'uri'
require 'genesis_collector'

module GenesisCollector
  class SimpleHTTP
    def initialize(host, headers: {}, timeout: 2)
      @host = host
      @headers = {'User-Agent' => GenesisCollector::USER_AGENT}.merge! headers
      @timeout = timeout
    end

    def patch(endpoint, payload = nil, headers = {})
      verb(endpoint, payload, headers) { |uri| Net::HTTP::Patch.new(uri) }
    end

    private

    def verb(endpoint, payload, headers)
      uri = URI.parse("#{@host}#{endpoint}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = http.read_timeout = http.ssl_timeout = @timeout
      http.use_ssl = true if @host.start_with?('https')
      request = yield uri.request_uri
      request.body = JSON.dump(payload) unless payload.nil?
      request = add_headers(request, headers)
      http.request(request)
    end

    def add_headers(request, headers)
      headers.merge!(@headers)
      headers.each do |k, v|
        request[k] = v
      end
      request
    end
  end
end
