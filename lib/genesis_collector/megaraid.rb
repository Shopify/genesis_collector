module GenesisCollector
  module MegaRaid

    def collect_megaraid
      @payload[:raids] ||= []
      @payload[:properties] ||= {}
      if megaraid?
        @payload[:properties]['MEGARAID_TYPE'] = read_megacli_adapter_type
        @payload[:properties]['MEGARAID_FW_PACKAGE'] = read_megacli_adapter_firmware
        @payload[:raids].concat read_megacli_logical_disks
      end
    end

    def megaraid?
      return !read_megacli_adapter_type.nil?
    end

    private

    def megacli_adapter_output()
      @megacli_adapter_output ||= shellout_with_timeout('megacli -AdpAllInfo -aAll', 10)
    end

    def read_megacli_adapter_type()
      match = megacli_adapter_output.match(/Product Name\s*:\s*(.+)\s*$/)
      return nil if match.nil?
      match[1]
    end

    def read_megacli_adapter_firmware()
      match = megacli_adapter_output.match(/FW Package Build\s*:\s*(\S+)$/)
      return nil if match.nil?
      match[1]
    end

    def read_megacli_logical_disks()
      @megacli_ld_output ||= shellout_with_timeout('megacli -LDInfo -Lall -aAll', 10)
      lds = []
      @megacli_ld_output.split(/^$/).each do |disk|
        lines = disk.split(/\n+/)
        next if lines.count < 5 # skip status and empty
        record = {}
        lines.each do |line|
          match = line.match(/\s*(.+?)\s*:\s*(.+)\s*$/)
          record[match[1]] = match[2] unless match.nil?
        end
        lds << record
      end
      lds
    end
  end
end
