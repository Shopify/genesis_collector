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
      end

      def report
        if defined?(Bugsnag)
          @bugsnag_config = Bugsnag::Configuration.new
          @bugsnag_config.api_key = @config.delete('bugsnag_api_key')
          @bugsnag_config.app_version = GenesisCollector::VERSION
          @bugsnag_config.project_root = File.expand_path('../../..', File.dirname(__FILE__))
          @bugsnag_config.release_stage = run_context.node.chef_environment
          @config[:error_handler] = ->(e) { Bugsnag::Notification.new(e, @bugsnag_config).deliver }
        end
        prepare_report
        send_report
      end

      private

      def prepare_report
        @collector = GenesisCollector::Collector.new(@config.merge(chef_node: run_context.node))
        @collector.collect!
      rescue => e
        Bugsnag::Notification.new(e, @bugsnag_config).deliver if defined?(Bugsnag)
        Chef::Log.error("Error collecting system information for Genesis:\n" + e.message)
        Chef::Log.error(e.backtrace.join("\n"))
      end

      def send_report
        @collector.submit!
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        Bugsnag::Notification.new(e, @bugsnag_config).deliver if defined?(Bugsnag)
        Chef::Log.error("Could not connect to Genesis. Connection error:\n" + e.message)
        Chef::Log.error(e.backtrace.join("\n"))
      end
    end
  end
end
