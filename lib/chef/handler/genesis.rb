require 'chef/handler'
require 'chef/mash'
require 'genesis_collector'

begin
  require 'bugsnag'
rescue LoadError
end

class Chef
  class Handler
    class Genesis < Chef::Handler
      attr_reader :config

      def initialize(config = {})
        @config = Mash.new(config)
        if defined?(Bugsnag)
          Bugsnag.configure do |config|
            config.api_key = @config.delete('bugsnag_api_key')
          end
        end
      end

      def report
        prepare_report
        send_report
      end

      private

      def prepare_report
        @collector = GenesisCollector::Collector.new(@config.merge(chef_node: run_context.node))
        @collector.collect!
      rescue => e
        Bugsnag.notify(e) if defined?(Bugsnag)
        Chef::Log.error("Error collecting system information for Genesis:\n" + e.message)
        Chef::Log.error(e.backtrace.join("\n"))
      end

      def send_report
        @collector.submit!
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        Bugsnag.notify(e) if defined?(Bugsnag)
        Chef::Log.error("Could not connect to Genesis. Connection error:\n" + e.message)
        Chef::Log.error(e.backtrace.join("\n"))
      end
    end
  end
end
