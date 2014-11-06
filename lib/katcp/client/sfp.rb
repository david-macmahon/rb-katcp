require 'katcp'

module KATCP
  class Sfp
    # Opcode for MDIO address operation
    OP_MDIO_ADDRESS  = 0b000
    # Opcode for MDIO read operation
    OP_MDIO_WRITE    = 0b010
    # Opcode for MDIO read-address-increment operation
    OP_MDIO_READ_INC = 0b100
    # Opcode for MDIO read operation
    OP_MDIO_READ     = 0b110
    # Opcode for CONF write operation
    OP_CONF_WRITE    = 0b011
    # Opcode for CONF read operation
    OP_CONF_READ     = 0b101

    # PHY addresses (within an SFP+ card) indexed by PHY index (0-7)
    PHY_ADDR = [
      0x0000, 0x0100, 0x1e00, 0x1f00, # Mezz 0
      0x0000, 0x0100, 0x1e00, 0x1f00  # Mezz 1
    ]

    # PHY reset bits (GPIO lines) indexed by PHY index (0-7).  Odd phys have
    # share reset line with even phy below it because reset is a chip level
    # operation.
    PHY_RESET_BITS = [
      0x0002, 0x0002, 0x0004, 0x0004, # Mezz 0
      0x0080, 0x0080, 0x0100, 0x0100  # Mezz 1
    ]

    # Constructor.  `_device_name` is currently unused (hence the leading '_').
    # It is declared for compatibility with KATCP::RoachClient's dynamic method
    # generation.
    def initialize(katcp_client, _device_name)
      if katcp_client.listdev.grep('sfp_mdio_sel').empty?
        raise 'sfp_mdio_sel device not found'
      end
      @katcp_client = katcp_client
    end

    # Accessor method should always/only be 'sfp_controller'.
    def self.method_name(method_name)
      'sfp_controller'
    end

    # Resets the PHYs passed as `phys`.  The lsb of the PHY (i.e. the chan
    # part) does not matter as this is a chip-level reset affecting both
    # channels of the given PHY chip.  IOW, reset(0) and reset(1) do exactly
    # the same thing.  Returns `self`.
    def reset_phys(*phys)
      # Default to all phy chips
      phys = [0, 2, 4, 6] if phys.empty?
      # Convert any ranges to arrays and flatten
      phys.map! {|o| Range === o ? o.to_a : o}
      phys.flatten!
      # Ensure all phys are in range 0, 2, 4, 6
      phys.map! {|i| i & 6}
      # Elimintate duplicate phys
      phys.uniq!
      # Build up reset value
      value = 0
      phys.each {|phy| value |= PHY_RESET_BITS[phy]}
      # Set output enable bits for value.
      # TODO Original code from SKA-SA did not save/restore output enable bits
      # so we don't either, should we?.
      @katcp_client['sfp_gpio_data_oe' ] = value
      @katcp_client['sfp_gpio_data_out'] = value
      @katcp_client['sfp_gpio_data_out'] = 0
      # Return self
      self
    end

    # Enable software control of SFP MDIOs.
    def enable_sw_control
      # Set the "sfp_gpio_data_ded" register to (presumably) allow MDIO data
      # and clock lines to go to the external PHYs (rather than go the internal
      # PHY or serve some other purpose).  The value used, 0x0618, is derived
      # from the following table described by other sources:
      #
      #               mgt_gpio[11] Unused
      #     ENABLE => mgt_gpio[10] SFP1: MDIO         MDIO data line
      #     ENABLE => mgt_gpio[9]  SFP1: MDC          MDIO clock line
      #               mgt_gpio[8]  SFP1: PHY1 RESET   PHY reset when '1'
      #               mgt_gpio[7]  SFP1: PHY0 RESET   PHY reset when '1'
      #               mgt_gpio[6]  SFP1: MDIO Enable  Enable MDIO mode when '1'
      #               mgt_gpio[5]  Unused 
      #     ENABLE => mgt_gpio[4]  SFP0: MDIO         MDIO data line
      #     ENABLE => mgt_gpio[3]  SFP0: MDC          MDIO clock line
      #               mgt_gpio[2]  SFP0: PHY1 RESET   PHY reset when '1'
      #               mgt_gpio[1]  SFP0: PHY0 RESET   PHY reset when '1'
      #               mgt_gpio[0]  SFP0: MDIO Enable  Enable MDIO mode when '1'
      @katcp_client['sfp_gpio_data_ded'] = 0x0618
      # set EMAC MDIO configuration clock divisor and enable MDIO
      do_op(OP_CONF_WRITE, 0x7f, 0x0340)
    end

    # Do a basic MDIO/CONF operation.  Read operations return the result.
    # Write operations returns `self`.  Note that `data` comes before `address`
    # because `data` is passed without `address` more often than `address` is
    # passed without `data`.
    def do_op(opcode, data=nil, address=nil)
      @katcp_client['sfp_op_type'] = opcode
      @katcp_client['sfp_op_data'] = data if data
      @katcp_client['sfp_op_addr'] = address if address
      @katcp_client['sfp_op_issue'] = 1
      (opcode & 0b100) == 0b100 ? @katcp_client['sfp_op_result'] : self
    end

    # Selects mezzanine `mezz` (0 or 1).  Returns `self`
    def select_mezz(mezz)
      if mezz != @mezz
        @katcp_client['sfp_mdio_sel'] = @mezz = mezz
      end
      self
    end

    # Reads MDIO register given by (`phy`, `address`) and returns the value.
    #
    # `phy` is 0 to 7 indicating the PHY to query.  Here is a table mapping
    # `phy` to mezzanine card, chip, and channel:
    #     phy   mezz   chip   chan
    #      0     0      0      0
    #      1     0      0      1
    #      2     0      1      0
    #      3     0      1      1
    #      4     1      0      0
    #      5     1      0      1
    #      6     1      1      0
    #      7     1      1      1
    #
    # The low 16 bits in `address` are the register address within the MMD
    # specified by the 5 bits immediately above the low 16 bits.
    def read_mdio(phy, address)
      mezz = (phy & 0b100) >> 2
      #chip = (phy & 0b010) >> 1
      #chan = (phy & 0b001)

      mmd     = (address & 0x1f_0000) >> 16
      address = (address & 0x00_ffff)

      select_mezz(mezz)
      enable_sw_control
      do_op(OP_MDIO_ADDRESS, address, PHY_ADDR[phy] + mmd)
      do_op(OP_MDIO_READ)
    end
    alias [] read_mdio

    # Writes `data` to MDIO register to (PHY, ADDRESS) given by (`phy`,
    # `address`).  Returns `self`.
    #
    # `phy` is 0 to 7 indicating the PHY to query.  Here is a table mapping
    # `phy` to mezzanine card, chip, and channel:
    #     phy   mezz   chip   chan
    #      0     0      0      0
    #      1     0      0      1
    #      2     0      1      0
    #      3     0      1      1
    #      4     1      0      0
    #      5     1      0      1
    #      6     1      1      0
    #      7     1      1      1
    #
    # The low 16 bits in `address` are the register address within the MMD
    # specified by the 5 bits immediately above the low 16 bits.
    def write_mdio(phy, address, data)
      mezz = (phy & 0b100) >> 2
      #chip = (phy & 0b010) >> 1
      #chan = (phy & 0b001)

      mmd     = (address & 0x1f_0000) >> 16
      address = (address & 0x00_ffff)

      select_mezz(mezz)
      enable_sw_control
      do_op(OP_MDIO_ADDRESS, address, PHY_ADDR[phy] + mmd)
      do_op(OP_MDIO_WRITE, data)
      self
    end
    alias []= write_mdio

    # Returns the contents of the Device ID register (should be 0x8488 ==
    # 33928) and the Device Revision register (typically 4 or 5) for PHY `phy`.
    def phy_id_rev(phy)
      phy_id  = self[phy, 0x1e_0000]
      phy_rev = self[phy, 0x1e_0001]
      [phy_id, phy_rev]
    end

    # Returns `true` if the device id of PHY `phy` is 0x8488, false if it is 0,
    # and nil if it is anything else.
    def phy_present?(phy)
      phy_id, _phy_rev = phy_id_rev(phy)
      case phy_id
      when 0x8488; true
      when 0x0000; false
      else nil
      end
    end

    # Returns the temperature of PHY `phy`.  Returns 233.5 (max possible
    # reading) on error conditions.  A real reading of 233.5 is its own type of
    # error condition!
    def read_temp(phy)
      # Start temp measurement
      self[phy, 0x1e_7fd6] = 0x5800
      # Loop up to 5 time until done
      temp = 0
      5.times do
        temp = self[phy, 0x1e_7fd6]
        break if (temp & 0x5c00) == 0x5400
      end
      # Make incompletes/errors have consistent value
      temp = 0 if (temp & 0x5c00) != 0x5400
      # Convert temp to Celcius
      (233500 - 1081 * (temp & 0xff)) / 1000.0
    end
  end
end
