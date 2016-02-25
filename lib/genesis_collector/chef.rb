module GenesisCollector
  module Chef

    def collect_chef
      @payload[:chef] = {
        environment: get_chef_environment,
        roles: (@chef_node.respond_to?(:[]) ? @chef_node['roles'] : []),
        run_list: (@chef_node.respond_to?(:[]) ? @chef_node['run_list'] : ''),
        tags: get_chef_tags
      }
    end

    def get_chef_environment
      env = nil
      env = File.read('/etc/chef/current_environment').gsub(/\s+/, '') if File.exist? '/etc/chef/current_environment'
      env || 'unknown'
    end

    def get_chef_tags
      node_show_output = shellout_with_timeout('knife node show `hostname` -c /etc/chef/client.rb')
      node_show_output.match(/Tags:(.*)/)[0].delete(' ').gsub('Tags:', '').split(',')
    rescue
      []
    end

  end
end
