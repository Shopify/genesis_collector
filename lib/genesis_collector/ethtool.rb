require 'socket'
require 'cstruct'

module GenesisCollector

  class EthernetInterface

    def initialize(interface)
      @interface = interface
    end

    def supported_speeds
      modes(read_interface(@interface).supported)
    end

    def link?
      read_interface_raw(@interface, EthtoolValue, ETHTOOL_CMD_GLINK).value != 0
    end

    def duplex
      case read_interface(@interface).duplex
      when 0 then :half
      when 1 then :full
      else        :unknown
      end
    end

    def port
      case read_interface(@interface).port
      when 0x00 then 'T'
      when 0x01 then 'AUI'
      when 0x02 then 'MII'
      when 0x03 then 'F'
      when 0x04 then 'BNC'
      when 0x05 then 'DA'
      when 0xef then 'NONE'
      when 0xff then 'OTHER'
      else          'Unknown'
      end
    end

    def speed
      link_speed = read_interface(@interface).speed
      link_speed = :unknown if link_speed == 65535
      Mode.new(link_speed, duplex, port)
    end

    def driver
      as_str(read_driver_data.driver)
    end

    def driver_version
      as_str(read_driver_data.version)
    end

    private

    # From /u/i/linux/sockios.h
    SIOCETHTOOL = 0x8946

    # Mask to read ethtool data
    ETHTOOL_CMD_GSET = 0x00000001

    # Mask to determine if there is a link
    ETHTOOL_CMD_GLINK = 0x0000000a

    # Mask to determine the driver info
    ETHTOOL_CMD_GDRVINFO = 0x00000003

    Mode = Struct.new(:speed, :duplex, :media)

    class Mode
      # Print out a more standard-looking representation for a mode
      def to_s
        if self.speed == :unknown
          "Unknown"
        else
          "#{self.speed}base#{self.media}/#{self.duplex}"
        end
      end
    end

    class EthtoolCmd < CStruct
      MASK = ETHTOOL_CMD_GSET

      uint32 :cmd
      uint32 :supported
      uint32 :advertising
      uint16 :speed
      uint8  :duplex
      uint8  :port
      uint8  :phy_address
      uint8  :transceiver
      uint8  :autoneg
      uint8  :mdio_support
      uint32 :maxtxpkt
      uint32 :maxrxpkt
      uint16 :speed_hi
      uint8  :eth_tp_mdix
      uint8  :reserved
      uint32 :lp_advertising
      uint32 :reserved2
      uint32 :reserved3
    end

    class EthtoolCmdDriver < CStruct
      MASK = ETHTOOL_CMD_GDRVINFO

      uint32 :cmd
      char   :driver,[32]
      char   :version,[32]
      char   :fw_version,[32]
      char   :bus_info,[32]
      char   :reserved1,[32]
      char   :reserved2,[16]
      uint32 :n_stats
      uint32 :testinfo_len
      uint32 :eedump_len
      uint32 :regdump_len
    end

    class EthtoolValue < CStruct
      int32 :cmd
      int32 :value
    end

    POSSIBLE_MODES = {
      1 << 0  => Mode.new(10, :half, 'T'),
      1 << 1  => Mode.new(10, :full, 'T'),
      1 << 2  => Mode.new(100, :half, 'T'),
      1 << 3  => Mode.new(100, :full, 'T'),
      1 << 4  => Mode.new(1000, :half, 'T'),
      1 << 5  => Mode.new(1000, :full, 'T'),
      1 << 12 => Mode.new(10000, :full, 'T'),
      1 << 15 => Mode.new(2500, :full, 'X'),
      1 << 17 => Mode.new(1000, :full, 'KX'),
      1 << 18 => Mode.new(10000, :full, 'KX4'),
      1 << 19 => Mode.new(10000, :full, 'KR'),
      1 << 20 => Mode.new(10000, :fec, 'R'),
      1 << 21 => Mode.new(20000, :full, 'MLD2'),
      1 << 22 => Mode.new(20000, :full, 'KR2'),
      1 << 23 => Mode.new(40000, :full, 'KR4'),
      1 << 24 => Mode.new(40000, :full, 'CR4'),
      1 << 25 => Mode.new(40000, :full, 'SR4'),
      1 << 26 => Mode.new(40000, :full, 'LR4'),
      1 << 27 => Mode.new(56000, :full, 'KR4'),
      1 << 28 => Mode.new(56000, :full, 'CR4'),
      1 << 29 => Mode.new(56000, :full, 'SR4'),
      1 << 30 => Mode.new(56000, :full, 'LR4'),
    }
    # Turn a uint32 of bits into a list of supported modes.  Sigh.
    def modes(data)
      POSSIBLE_MODES.find_all { |m| (m[0] & data) > 0 }.map { |m| m[1] }
    end

    # Turn a raw C char array into a ruby str
    def as_str(str)
      str.pack('c*').delete("\000")
    end

    def ioctl(interface, ecmd)
      sock = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM, 0)
      rv = ecmd.clone
      ifreq = [interface, ecmd.data].pack("a16P#{rv.data.length}")
      sock.ioctl(SIOCETHTOOL, ifreq)
      rv
    end

    def read_interface(interface)
      read_interface_raw(interface, EthtoolCmd, EthtoolCmd::MASK)
    end

    def read_driver_data
      read_interface_raw(@interface, EthtoolCmdDriver, EthtoolCmdDriver::MASK)
    end

    def read_interface_raw(interface, struct, mask)
      v = struct.new
      v.cmd = mask
      ioctl(interface, v)
    end
  end
end
