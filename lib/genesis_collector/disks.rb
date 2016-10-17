module GenesisCollector
  module Disks

    def collect_disks
      ensure_command('smartctl')
      ensure_command('blkid')
      @payload[:disks] = enumerate_disks
      @payload[:disks].each do |d|
        info = get_disk_info(d.delete(:smartctl_cmd))
        d[:vendor_name] = info.match(/^Vendor:\s+(.*)$/)[1] rescue nil
        d[:vendor_name] ||= info.match(/^Device Model:\s+(\w+)[_ ](?:.*)$/)[1] rescue nil
        d[:product] = info.match(/^(?:Device Model|Product):\s+(.*)$/)[1]
        d[:serial_number] = info.match(/^Serial (?:n|N)umber:\s+(.*)$/)[1] rescue nil
        d[:size] = info.match(/^User Capacity:\s+(.*)$/)[1].split('bytes')[0].strip.gsub(',', '')
        d[:slot] = get_scsi_slot(d[:dev]) if d[:dev] =~ /^\/dev\/sd/
        d[:uuid] = disk_uuid(d[:dev]) if d[:dev] =~ /^\/dev\/sd/
      end
      @payload[:disks].delete_if { |d| d[:serial_number].nil? }
    rescue StandardError => ex
      # Just to be sure we don't send partial data
      @payload.delete(:disks)
      raise ex
    end

    private

    def enumerate_disks
      raw = shellout_with_timeout('smartctl --scan').strip
      raw.split("\n").map do |line|
        parts = line.split('#')
        {
          smartctl_cmd: parts[0].gsub('-d scsi', '').strip,
          dev: parts[1].split(',')[0].strip.split(' ')[0],
          kind: parts[1].split(',')[1].strip
        }
      end
    end

    def get_disk_info(cmd_params)
      shellout_with_timeout("smartctl -i #{cmd_params}", 5)
    end

    def disk_uuid(drive)
      blk_id = blkid.detect { |s| s.include? drive }
      /UUID="([^ ]*)"/.match(blk_id, 1)[1]
    end

    def blkid
      @blkid ||= shellout_with_timeout('blkid', 5).split("\n")
    end

    # FIXME - we might want to handle raid devices differently by parsing megacli
    def get_scsi_slot(device)
      File.basename(File.readlink("/sys/class/block/#{File.basename(device)}/device"))
    end
  end
end
