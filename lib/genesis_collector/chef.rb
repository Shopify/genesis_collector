require 'time'

module GenesisCollector
  module Chef

    def collect_chef
      @payload[:chef] = @chef_node.nil? ? collect_chef_from_knife : collect_chef_from_node
    end

    def collect_chef_from_node
      {
        environment: @chef_node.chef_environment,
        roles: @chef_node.roles,
        run_list: @chef_node.run_list.to_s,
        tags: @chef_node.tags,
        last_run: Time.at(@chef_node.ohai_time).utc.iso8601
      }
    end

    def collect_chef_from_knife
      output = shellout_with_timeout('knife node show `hostname` -c /etc/chef/client.rb -a ohai_time -a run_list -a tags -a environment -a roles -f json')
      _hostname, parsed = JSON.parse(output).first
      {
        environment: parsed['environment'],
        roles: parsed['roles'],
        run_list: parsed['run_list'].join(', '),
        tags: parsed['tags'],
        last_run: Time.at(parsed['ohai_time']).utc.iso8601
      }
    rescue
      nil
    end

  end
end
