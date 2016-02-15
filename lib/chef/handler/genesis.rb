require 'chef/handler'
require 'chef/mash'

class Chef
  class Handler
    class Genesis < Chef::Handler
      attr_reader :config

      def initialize(config = {})
        @config = Mash.new(config)
      end

      def report
        prepare_report
        send_report
      end

      private

      def prepare_report
        @collector = GenesisCollector.Collector.new(@config)
        @collector.collect!
      rescue => e
        Chef::Log.error("Error collecting system information for Genesis:\n" + e.message)
        Chef::Log.error(e.backtrace.join("\n"))
      end

      def send_report
        @collector.submit!
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        Chef::Log.error("Could not connect to Genesis. Connection error:\n" + e.message)
        Chef::Log.error(e.backtrace.join("\n"))
      end
    end
  end
end
