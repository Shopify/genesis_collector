require 'genesis_collector/lshw_parser'

module GenesisCollector
  module Lshw

    def get_lshw_data
      @lshw_data ||= GenesisCollector::LshwParser.new(shellout_with_timeout('lshw -xml', 40).strip)
    end

  end
end
