module GenesisCollector
  module DmiDecode

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
        when /^Handle\s+(.*?),\s+/
          handle = $1.to_i(16)
        when /(.*)\s+Information\n$/, /(.*)\s+Device\n$/, /(.*)\s+Device Mapped Address\n$/, /(.*)\s+Array Mapped Address\n$/, /Physical\s+(.*)\s+Array\n$/
          title = standardize_dmi_key($1)
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
