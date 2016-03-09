module GenesisCollector
  module DmiDecode

    DMI_TYPES = {
      0 => 'bios',
      1 => 'system',
      2 => 'base_board',
      3 => 'chassis',
      4 => 'processor',
      5 => 'memory_controller',
      6 => 'memory_module',
      7 => 'cache',
      8 => 'port_connector',
      9 => 'system_slots',
      10 => 'on_board_devices',
      11 => 'oem_strings',
      12 => 'system_configuration_options',
      13 => 'bios_language',
      14 => 'group_associations',
      15 => 'system_event_log',
      16 => 'physical_memory_array',
      17 => 'memory_device',
      18 => '32_bit_memory_error',
      19 => 'memory_array_mapped_address',
      20 => 'memory_device_mapped_address',
      21 => 'builtin_pointing_device',
      22 => 'portable_battery',
      23 => 'system_reset',
      24 => 'hardware_security',
      25 => 'system_power_controls',
      26 => 'voltage_probe',
      27 => 'cooling_device',
      28 => 'temperature_probe',
      29 => 'electrical_current_probe',
      30 => 'out_of_band_remote_access',
      31 => 'boot_integrity_services',
      32 => 'system_boot',
      33 => '64_bit_memory_error',
      34 => 'management_device',
      35 => 'management_device_component',
      36 => 'management_device_threshold data',
      37 => 'memory_channel',
      38 => 'ipmi_device',
      39 => 'power_supply',
      40 => 'additional_information',
      41 => 'onboard_device',
      127 => 'end_of_table'
    }

    def get_dmi_data
      @dmi_data ||= parse_dmidecode(shellout_with_timeout('dmidecode --type processor --type memory'))
    end

    def parse_dmidecode(data)
      dict={}
      handle = 0
      current_title = nil

      data.lines.each do |line|
        case line
        when /^End Of Table/, /^\s+$/, /^\# dmidecode/, /^SMBIOS/, /structures occupying/, /^Table at/
          next
        when /^Handle\s+(.*?), DMI type (.*?),\s+/
          handle = $1.to_i(16)
          type_id = $2.to_i
          title = DMI_TYPES[type_id]
          next if title == 'end_of_table'
          current_title = title
          dict[title] ||= []
          dict[title] << {'handle' => handle}
        else
          raw_data = line.strip.split(':')
          if raw_data.is_a?(Array) && raw_data.length == 2
            k, v = raw_data
            dict[current_title].last[standardize_dmi_key(k)] = v.strip
          end
        end
      end
      dict
    end

    private

    def standardize_dmi_key(k)
      k.downcase.gsub(/\s+/,'_')
    end
  end
end
