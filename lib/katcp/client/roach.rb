require 'katcp/client'

# Holds KATCP related classes etc.
module KATCP

  # Facilitates talking to <tt>tcpborphserver2</tt>, a KATCP server
  # implementation that runs on ROACH boards.  Mostly just adds convenience
  # methods for tab completion in irb.
  #
  #   TODO: Add conveneince methods for converting binary payload data.
  class RoachClient < Client

    # call-seq:
    #  delbof(image_file) -> KATCP::Response
    #
    # Deletes gateware image file named by +image_file+.
    def delbof(image_file)
      request(:delbof, image_file)
    end

    # call-seq:
    # echotest(ip_address, echo_port, byte_count) -> KATCP::Response
    #
    # Basic network echo tester.
    def echotest(ip_address, echo_port, byte_count)
      request(:echotest, ip_address, echo_port, byte_count)
    end

    # call-seq:
    #  listbof -> KATCP::Response
    #
    # Lists available gateware images.
    def listbof
      request(:listbof).sort!
    end

    # call-seq:
    #  listdev -> KATCP::Response
    #
    # Lists available registers.
    def listdev
      request(:listdev, :size).sort!
    end

    # call-seq:
    #   progdev -> KATCP::Response
    #   progdev(image_file) -> KATCP::Response
    #
    # Programs a gateware image specified by +image_file+.  If +image_file+ is
    # omitted, de-programs the FPGA.
    def progdev(*args)
      request(:progdev, *args)
    end

    # call-seq:
    #   read(register_name) -> KATCP::Response
    #   read(register_name, register_offset) -> KATCP::Response
    #   read(register_name, register_offset, byte_count) -> KATCP::Response
    #
    # Reads a +byte_count+ bytes starting at +register_offset+ offset from
    # register (or block RAM) named by +register_name+.  Binary data can be
    # obtained from the Response via the Response#payload method.
    def read(register_name, *args)
      request(:read, register_name, *args)
    end

    # call-seq:
    #  status -> KATCP::Response
    #
    # Reports if gateware has been programmed.
    def status
      request(:status)
    end

    # call-seq:
    #  sysinit -> KATCP::Response
    #
    # Writes the timing ctl register that resets the entire system.
    #
    # [Presumably this depends on a certain register naming convention?]
    def sysinit
      request(:sysinit)
    end

    # call-seq:
    #   tap_start(tap_device register_name, ip_address) -> KATCP::Response
    #   tap_start(tap_device register_name, ip_address, port) -> KATCP::Response
    #   tap_start(tap_device register_name, ip_address, port, mac) -> KATCP::Response
    #
    # Start a tgtap instance.
    def tap_start(tap_device, register_name, ip_address, *args)
      request(:tap_start, tap_device, register_name, ip_address, *args)
    end

    # call-seq:
    #  tap_stop(register_name) -> KATCP::Response
    #
    # Stop a tgtap instance.
    def tap_stop(register_name)
      request(:tap_stop, register_name)
    end

    # call-seq:
    #   uploadbof(net_port, filename) -> KATCP::Response
    #   uploadbof(net_port, filename, size) -> KATCP::Response
    #
    # Upload a gateware image.
    #
    #   NOT YET IMPLEMENTED
    def uploadbof(net_port, filename, *args)
      raise NotImplementedError.new('uploadbof not yet implemented')
    end

    # call-seq:
    #   wordread(register_name) -> KATCP::Response
    #   wordread(register_name, word_offset) -> KATCP::Response
    #   wordread(register_name, word_offset, length) -> KATCP::Response
    #
    # Reads word(s) from +register_name+.
    def wordread(register_name, *args)
      request(:wordread, register_name, *args)
    end

    # call-seq:
    #   wordwrite(register_name, payload) -> KATCP::Response
    #   wordwrite(register_name, word_offset, payload[, ...]) -> KATCP::Response
    #
    # Writes one or more words to a register (or block RAM).  The first form
    # uses a word offset of 0.
    def wordwrite(register_name, *args)
      word_offset = (args.length == 1) ? 0 : args.shift
      request(:wordwrite, register_name, word_offset, *args)
    end

    # call-seq:
    # write(register_name, register_offset, data_payload) -> KATCP::Response
    #
    # Write a given payload to an offset in a register.
    def write(register_name, register_offset, data_payload)
      request(:write, register_name, register_offset, data_payload)
    end

  end # class RoachClient
end # module KATCP
