require 'katcp/client'

# Holds KATCP related classes etc.
module KATCP

  # Facilitates talking to <tt>tcpborphserver2</tt>, a KATCP server
  # implementation that runs on ROACH boards.  Mostly just adds convenience
  # methods for tab completion in irb.
  class RoachClient < Client

    # call-seq:
    #   bulkread(register_name) -> KATCP::Response
    #   bulkread(register_name, register_offset) -> KATCP::Response
    #   bulkread(register_name, register_offset, byte_count) -> KATCP::Response
    #
    # Reads a +byte_count+ bytes starting at +register_offset+ offset from
    # register (or block RAM) named by +register_name+.  Returns a String
    # containing the binary data.
    def bulkread(register_name, *args)
      resp = request(:bulkread, register_name, *args)
      raise resp.to_s unless resp.ok?
      resp.lines[0..-2].map{|l| l[1]}.join
    end

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
    #   read(register_name) -> Integer
    #   read(register_name, word_offset) -> Integer
    #   read(register_name, word_offset, word_count) -> NArray.int(word_count)
    #
    # Reads one or +word_count+ words starting at +word_offset+ offset from
    # register (or block RAM) named by +register_name+.  Returns an Integer
    # unless +word_count+ is given in which case it returns an
    # NArray.int(word_count).
    #
    # Note that KATCP::Client#read deals with byte-based offsets and counts,
    # but all reads on the ROACH must be word aligned and an integer number of
    # words long, so KATCP::RoachClient#read deals with word-based offsets and
    # counts.
    def read(register_name, *args)
      if args.length <= 1
        resp = request(:wordread, register_name, *args)
        raise resp.to_s unless resp.ok?
        resp.payload.to_i(0)
      else
        byte_offset = 4 * args[0]
        byte_count = 4 * args[1]
        resp = request(:read, register_name, byte_offset, byte_count)
        raise resp.to_s unless resp.ok?
        resp.payload.to_na(NArray::INT).ntoh
      end
    end

    alias wordread read
    alias [] read

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
    #   write(register_name, data) -> self
    #   write(register_name, word_offset, data) -> self
    #
    # Write the given data (typically an NArray.int) to +word_offset+ (0 if not
    # given) in register named +register_name+.  +data+ can be String
    # containing raw bytes, NArray.int, Array of integer values, or other
    # object that responds to to_i.
    def write(register_name, *args)
      word_offset = (args.length > 1) ? args.shift : 0
      byte_offset = 4 * word_offset
      args.flatten!
      args.map! do |a|
        case a
        when String; a
        when NArray; a.hton.to_s
        when Array; a.pack('N*')
        else [a.to_i].pack('N*')
        end
      end
      data = args.join
      byte_count = data.length
      if byte_count % 4 != 0
        raise "data length of #{byte_count} bytes is not a multiple of 4 bytes"
      elsif byte_count == 0
        warn "writing 0 bytes to #{register_name}"
      end
      resp = request(:write, register_name, register_offset, data)
      raise resp.to_s unless resp.ok?
      self
    end

    alias wordwrite write
    alias []= write

  end # class RoachClient
end # module KATCP
