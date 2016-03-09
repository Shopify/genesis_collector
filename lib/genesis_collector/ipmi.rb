module GenesisCollector
  module IPMI

    def collect_ipmi
      @payload[:ipmi] = {
        address: read_ipmi_attribute('IP Address'),
        netmask: read_ipmi_attribute('Subnet Mask'),
        mac: read_ipmi_attribute('MAC Address'),
        gateway: read_ipmi_attribute('Default Gateway IP')
      }
    end

    private

    def read_ipmi_attribute(key)
      @ipmi_lan_output ||= shellout_with_timeout('ipmitool lan print', 10)
      @ipmi_lan_output.match(/#{key}\s*:\s*(\S+)$/)[1] || 'unknown'
    end

    def read_ipmi_fru(key)
      data = shellout_with_timeout('ipmitool fru')
      data.match(/#{key}\s*:\s*(\S+)$/)[1] || 'unknown'
    end

  end
end
