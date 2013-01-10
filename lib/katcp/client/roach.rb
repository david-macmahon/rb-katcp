require 'katcp/client'

# Holds KATCP related classes etc.
module KATCP

  # Class used to access BRAMs
  class Bram
    def initialize(katcp_client, bram_name)
      @katcp_client = katcp_client
      @bram_name = bram_name
    end

    # Calls @katcp_client.bulkread(@bram_name, *args)
    def [](*args)
      @katcp_client.bulkread(@bram_name, *args)
    end

    # Calls @katcp_client.write(@bram_name, *args)
    def []=(*args)
      @katcp_client.write(@bram_name, *args)
    end
  end

  # Facilitates talking to <tt>tcpborphserver2</tt>, a KATCP server
  # implementation that runs on ROACH boards.  In addition to providing
  # convenience wrappers around <tt>tcpborphserver2</tt> requests, it also adds
  # the following features:
  #
  # * Hash-like access to read and write gateware devices (e.g. software
  #   registers, shared BRAM, etc.) via methods #[] and #[]=.
  #
  # * Each RoachClient instance dynamically adds (and removes) reader and
  #   writer attributes (i.e. methods) for gateware devices as the FPGA is
  #   programmed (or de-programmed).  This not only provides for very clean and
  #   readable code, it also provides convenient tab completion in irb for
  #   gateware specific device names.  Subclasses can exert some control over
  #   the dynamic method genreation.  See #device_typemap for details.
  #
  # * Word based instead of byte based data offsets and counts.  KATCP::Client
  #   data transfer methods #read and #write deal with byte based offsets and
  #   counts.  These methods in KATCP::RoachClient deal with word based offsets
  #   and counts since ROACH transfers (currently) require word alignment in
  #   both offsets and counts.  To use byte based offsets and counts
  #   explicitly, use <tt>request(:read, ...)</tt> instead of
  #   <tt>read(...)</tt> etc.
  class RoachClient < Client

    # Returns an Array of Strings representing the device names from the
    # current design.  The Array will be empty if the currently programmed
    # gateware has no devices (very rare, if even possible) or if no gateware
    # is currently programmed.
    attr_reader :devices

    # call-seq: RoachClient.new([remote_host, remote_port=7147, local_host=nil, local_port=nil,] opts={}) -> RoachClient
    #
    # Creates a RoachClient that connects to a KATCP server at +remote_host+ on
    # +remote_port+.  If +local_host+ and +local_port+ are specified, then
    # those parameters are used on the local end to establish the connection.
    # Positional parameters can be used OR parameters can be passed via the
    # +opts+ Hash.
    #
    # Supported keys for the +opts+ Hash are:
    #
    #   :remote_host  Specifies hostname of KATCP server
    #   :remote_port  Specifies port used by KATCP server (default 7147)
    #   :local_host   Specifies local interface to bind to (default nil)
    #   :local_port   Specifies local port to bind to (default nil)
    #   :typemap      Provides a default device typemap (default {}).
    #                 See #device_typemap for details.
    def initialize(*args)
      # List of all devices
      @devices = [];
      # List of dynamically defined device attrs (readers only, writers implied)
      @device_attrs = [];
      # Hash of created Bram objects
      @brams = {}
      # Call super *after* initializing subclass instance variables
      super(*args)
    end

    # Override KATCP::Client#connect to perform subclass specific
    # post-connection setup.
    def connect
      super
      # Determine which commands are supported by the server
      commands = request(:help).to_s
      # Determine whether bulkread is used by server
      @bulkread = commands.index('#help bulkread') ? :bulkread : :read
      # Determine whether status or fpgastatus command is used by server
      @fpgastatus = commands.index('#help fpgastatus') ? :fpgastatus : :status
      # Define device-specific attributes (if device is programmed)
      define_device_attrs
      self
    end

    # Override KATCP::Client#close to perform subclass specific post-close
    # cleanup.  Be sure to call super afterwards!
    def close
      # Undefine device-specific attributes (if device is programmed)
      undefine_device_attrs
    ensure
      super
    end

    # Dynamically define attributes (i.e. methods) for gateware devices, if
    # currently programmed.  See #device_typemap for more details.
    def define_device_attrs # :nodoc:
      # First undefine existing device attrs
      undefine_device_attrs
      # Define nothing if FPGA not programmed
      return unless programmed?
      # Get device typemap (possibly from subclass override!)
      typemap = device_typemap || {}
      # Dynamically define accessors for all devices (i.e. registers, BRAMs,
      # etc.) except those whose names conflict with existing methods.
      @devices = listdev.lines[0..-2].map {|l| l[1]}
      @devices.sort!
      @devices.each do |dev|
        # TODO sanitize dev in case it is invalid method name

        # Define methods unless they conflict with existing methods
        if ! respond_to?(dev) && ! respond_to?("#{dev}=")
          # Determine type (and aliases) of this device
          type, *aliases = typemap[dev] || typemap[dev.to_sym]
          next if type == :skip
          # Dynamically define methods and aliases
          case type
          when :bram;  bram(dev, *aliases)
          when :roreg; roreg(dev, *aliases)
          # else :rwreg or nil (or anything else for that matter) so treat it
          # as R/W register.
          else rwreg(dev, *aliases)
          end
        end
      end
      self
    end

    protected :define_device_attrs

    # Undefine any attributes (i.e. methods) and aliases that were previously
    # defined dynamically.
    def undefine_device_attrs # :nodoc:
      @device_attrs.each do |name|
        instance_eval "class << self; remove_method '#{name}'; end"
      end
      @device_attrs.clear
      @devices.clear
      @brams.clear
      self
    end

    protected :undefine_device_attrs

    # This method's return value controls how methods and aliases are
    # dynamically generated for devices within the ROACH gateware.  If
    # #device_typemap returns +nil+ or an empty Hash, all devices will be
    # treated as read/write registers.  Otherwise, #device_typemap must
    # return a Hash-like object.  If the object returned by #device_typemap
    # contains a key (String or Symbol) for a given device name, the key's
    # corresponding value specifies how to treat that device when dynamically
    # generating accessor methods for it and whether to generate any aliases
    # for it.  If no key exists for a given device, the device will be treated
    # as a read/write register.  The corresponding value can be one of:
    #
    #   :roreg (Read-only register)  Only a reader method will be created.
    #   :rwreg (Read-write register) Both reader and writer methods will be
    #                                created.
    #   :bram (Shared BRAM)          A reader method returning a Bram object
    #                                will be created.  The returned Bram object
    #                                provides convenient ways to read and write
    #                                to the Bram device.
    #   :skip (unwanted device)      No method will be created.
    #
    # Methods are only created for devices that actually exist on the device.
    # If no device exists for a given key, no methods will be created for that
    # key.  In other words, regardless of the keys given, methods will not be
    # created unless they are backed by an actual device.  Both reader and
    # writer methods are created for devices for which no key is present.
    #
    # The value can also be an Array whose first element is a Symbol from the
    # list above.  The remaining elements specify aliases to be created for the
    # given attribute methods.
    #
    # RoachClient#device_typemap returns on empty Hash so all devices are
    # treated as read/write registers by default.  Gateware specific subclasses
    # of RoachClient can override #device_typemap method to return a object
    # containing a Hash tailored to a specific gateware design.
    #
    # Example: The following would lead to the creation of the following
    # methods and aliases: "input_selector", "input_selector=", "insel",
    # "insel=", "switch_gbe_status", "adc_rms_levels" (assuming the named
    # devices all exist!).  No methods would be created for the device named
    # "unwanted_reg" even if it exists.
    #
    #   class MyRoachDesign < RoachClient
    #     DEVICE_TYPEMAP = {
    #       :input_selector    => [:rwreg, :insel],
    #       :switch_gbe_status => :roreg,
    #       :adc_rms_levels    => :bram,
    #       :unwanted_reg      => :skip
    #     }
    #
    #     def device_typemap
    #       DEVICE_TYPEMAP
    #     end
    #   end
    #
    # Returns the default device typemap Hash (either the one passed to the
    # constructor or an empty Hash).  Design specific subclasses can override
    # this method to return a design specific device typemap.
    def device_typemap
      (@opts && @opts[:typemap]) || {}
    end

    # Allow subclasses to create read accessor method (with optional aliases)
    # Create read accessor method (with optional aliases)
    # for register.  Converts reg_name to method name by replacing '/' with
    # '_'.  Typically used with read-only registers.
    def roreg(reg_name, *aliases) # :nodoc:
      method_name = reg_name.to_s.gsub('/', '_')
      instance_eval <<-"_end"
        class << self
          def #{method_name}(off=0,len=1); read('#{reg_name}',off,len); end
        end
      _end
      @device_attrs << method_name
      aliases.each do |a|
        a = a.to_s.gsub('/', '_')
        instance_eval "class << self; alias #{a} #{method_name}; end"
        @device_attrs << a
      end
      self
    end

    protected :roreg

    # Allow subclasses to create read and write accessor methods (with optional
    # Create read and write accessor methods (with optional
    # aliases) for register.  Converts reg_name to method name by replacing '/'
    # with '_'.
    def rwreg(reg_name, *aliases) # :nodoc:
      roreg(reg_name, *aliases)
      method_name = reg_name.to_s.gsub('/', '_')
      instance_eval <<-"_end"
        class << self
          def #{method_name}=(v,off=0); write('#{reg_name}',off,v); end
        end
      _end
      @device_attrs << "#{method_name}="
      aliases.each do |a|
        a = a.to_s.gsub('/', '_')
        instance_eval "class << self; alias #{a}= #{method_name}=; end"
        @device_attrs << "#{a}="
      end
      self
    end

    protected :rwreg

    # Allow subclasses to create accessor method (with optional aliases) for
    # Create accessor method (with optional aliases) for
    # Bram object backed by BRAM.
    def bram(bram_name, *aliases) # :nodoc:
      bram_name = bram_name.to_s
      method_name = bram_name.gsub('/', '_')
      instance_eval <<-"_end"
        class << self
          def #{method_name}()
            @brams['#{bram_name}'] ||= Bram.new(self, '#{bram_name}')
            @brams['#{bram_name}']
          end
        end
      _end
      @device_attrs << method_name
      aliases.each do |a|
        a = a.to_s.gsub('/', '_')
        instance_eval "class << self; alias #{a} #{method_name}; end"
        @device_attrs << "#{a}"
      end
      self
    end

    protected :bram

    # Returns +true+ if the current design has a device named +device+.
    def has_device?(device)
      @devices.include?(device.to_s)
    end

    # Provides Hash-like querying for a device named +device+.
    alias has_key? has_device?

    # call-seq:
    #   bulkread(register_name) -> Integer
    #   bulkread(register_name, word_offset) -> Integer
    #   bulkread(register_name, word_offset, word_count) -> NArray.int(word_count)
    #
    # Reads a +word_count+ words starting at +word_offset+ offset from
    # register (or block RAM) named by +register_name+.  Returns an Integer
    # unless +word_count+ is given in which case it returns an
    # NArray.int(word_count).
    #
    # Equivalent to #read (but uses a bulkread request rather than a read
    # request if bulkread is supported).
    def bulkread(register_name, *args)
      # Defer to #read unless server provides bulkread command
      return read(register_name, *args) unless @bulkread == :bulkread

      byte_offset = 4 * (args[0] || 0)
      byte_count  = 4 * (args[1] || 1)
      raise 'word count must be non-negative' if byte_count < 0
      resp = request(:bulkread, register_name, byte_offset, byte_count)
      raise resp.to_s unless resp.ok?
      data = resp.lines[0..-2].map{|l| l[1]}.join
      if args.length <= 1 || args[1] == 1
        data.unpack('N')[0]
      else
        data.to_na(NArray::INT).ntoh
      end
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

    # This is the default timeout to use when programming a bitstream via
    # #progdev.
    PROGDEV_SOCKET_TIMEOUT = 5

    # call-seq:
    #   progdev -> KATCP::Response
    #   progdev(image_file) -> KATCP::Response
    #
    # Programs a gateware image specified by +image_file+.  If +image_file+ is
    # omitted or nil, de-programs the FPGA.
    #
    # Whenever the FPGA is programmed, reader and writer attributes (i.e.
    # methods) are defined for every device listed by #listdev except for
    # device names that conflict with an already existing method names.
    #
    # Whenever the FPGA is de-programmed (or re-programmed), existing
    # attributes that were dynamically defined for the previous design are
    # removed.
    def progdev(*args)
      prev_socket_timeout = @socket_timeout
      begin
        # Adjust @socket_timeout if programming a bitstream
        @socket_timeout = PROGDEV_SOCKET_TIMEOUT if args[0]
        request(:progdev, *args)
      ensure
        @socket_timeout = prev_socket_timeout
      end
      define_device_attrs
    end

    # Returns true if currently programmed (specifically, it is equivalent to
    # <tt>request(@fpgastatus).ok?</tt>).  Older versions of tcpborphserver
    # used the "status" command, while newer versions use the "fpgastatus"
    # command for the same purpose.  The @connect method checks which is used
    # by the server and sets @fpgastatus accordingly.
    def programmed?
      status.ok?
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
    # Note that KATCP::Client#read deals with byte based offsets and counts,
    # but all reads on the ROACH must be word aligned and an integer number of
    # words long, so KATCP::RoachClient#read deals with word based offsets and
    # counts.
    def read(register_name, *args)
      byte_offset = 4 * (args[0] || 0)
      byte_count  = 4 * (args[1] || 1)
      raise 'word count must be non-negative' if byte_count < 0
      resp = request(:read, register_name, byte_offset, byte_count)
      raise resp.to_s unless resp.ok?
      data = resp.payload
      if args.length <= 1 || args[1] == 1
        data.unpack('N')[0]
      else
        data.to_na(NArray::INT).ntoh
      end
    end

    alias wordread read
    alias [] read

    # call-seq:
    #  status -> KATCP::Response
    #
    # Reports if gateware has been programmed.
    def status
      request(@fpgastatus||:status)
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
    # Write +data+ to +word_offset+ (0 if not given) in register named
    # +register_name+.  The +data+ argument can be a String containing raw
    # bytes (byte length must be multiple of 4), NArray.int, Array of integer
    # values, or other object that responds to #to_i.
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
      resp = request(:write, register_name, byte_offset, data, byte_count)
      raise resp.to_s unless resp.ok?
      self
    end

    alias wordwrite write
    alias []= write

  end # class RoachClient
end # module KATCP
