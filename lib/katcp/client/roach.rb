require 'katcp/client'

# Holds KATCP related classes etc.
module KATCP

  # Facilitates talking to <tt>tcpborphserver2</tt>, a KATCP server
  # implementation that runs on ROACH boards.  Mostly just adds convenience
  # methods for tab completion in irb.
  #
  #   TODO: Add conveneince methods for converting binary payload data.
  class RoachClient < Client

    # Deletes gateware image file named by +image_file+.
    def delbof(image_file)
      request(:delbof, image_file)
    end

    # Basic network echo tester.
    def echotest(ip_address, echo_port, byte_count)
      request(:echotest, ip_address, echo_port, byte_count)
    end

    # Lists available gateware images.
    def listbof
      request(:listbof).sort!
    end

    # Lists available registers.
    def listdev
      request(:listdev).sort!
    end

    # call-seq:
    #   progdev([image_file])
    #
    # Programs a gateware image specified by +image_file+.  If +image_file+ is
    # omitted, de-programs the FPGA.
    def progdev(*args)
      request(:progdev, *args)
    end

    # call-seq:
    #   read(register_name, [register_offset[, byte_count]])
    #
    # Reads a +byte_count+ bytes starting at +register_offset+ offset from
    # register (or block RAM) named by +register_name+.  Binary data can be
    # obtained from the Response via the Response#payload method.
    def read(register_name, *args)
      request(:read, register_name, *args)
    end

    # Reports if gateware has been programmed.
    def status
      request(:status)
    end

    # Writes the timing ctl register that resets the entire system.
    #
    # [Presumably this depends on a certain register naming convention?]
    def sysinit
      request(:sysinit)
    end

    # call-seq:
    #   tap_start(tap_device register_name, ip_address, [port[, mac]])
    #
    # Start a tgtap instance.
    def tap_start(tap_device, register_name, ip_address, *args)
      request(:tap_start, tap_device, register_name, ip_address, *args)
    end

    # Stop a tgtap instance.
    def tap_stop(register_name)
      reqest(:tap_stop, register_name)
    end

    # call-seq:
    #   uploadbof(net_port, filename[, size])
    #
    # Upload a gateware image.
    def uploadbof(net_port, filename, *args)
      raise NotImplementedError.new('uploadbof not yet implemented')
    end

    # call-seq:
    #   wordread(register_name[, word_offset[, length]])
    #
    # Reads words from +register_name+.
    def wordread(register_name, *args)
      request(:wordread, register_name, *args)
    end

    # call-seq:
    #   wordwrite(register_name, word_offset, payload[, ...])
    #
    # Writes one or more words to a register (or block RAM).
    def wordwrite(register_name, word_offset, *args)
      request(:wordwrite, register_name, word_offset, *args)
    end

    # Write a given payload to an offset in a register.
    def write(register_name, register_offset, data_payload)
      request(:write, register_name, register_offset, data_payload)
    end

  end # class RoachClient
end # module KATCP
