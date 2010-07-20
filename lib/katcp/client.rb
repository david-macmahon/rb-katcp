require 'monitor'
require 'socket'

require 'katcp/response'
require 'katcp/util'

# Holds KATCP related classes etc.
module KATCP

  # Facilitates talking to a KATCP server.
  class Client

    # Creates a KATCP client that connects to a KATCP server at +remote_host+
    # on +remote_port+.  If +local_host+ and +local_port+ are specified, then
    # those parameters are used on the local end to establish the connection.
    def initialize(remote_host, remote_port=7147, local_host=nil, local_port=nil)

      # Save remote_host and remote_port for #inspect
      @remote_host = remote_host
      @remote_port = remote_port

      # @socket is the socket connecting to the KATCP server
      @socket = TCPSocket.new(remote_host, remote_port, local_host, local_port)

      # Init attribute(s)
      @informs = []

      # @reqlock is the Monitor object used to serialize requests sent to the
      # KATCP server.  Threads should not write to @socket or read from @rxq
      # or change @reqname unless they have acquired (i.e. synchonized on)
      # @reqlock.
      @reqlock = Monitor.new

      # @reqname is the request name currently being processed (nil if no
      # current request).
      @reqname = nil

      # @rxq is an inter-thread queue
      @rxq = Queue.new

      # Start thread that reads data from server.
      Thread.new do
        # TODO: Monkey-patch gets so that it recognizes "\r" or "\n" as line
        # endings.  Currently only recognizes fixed strings, so for now go with
        # "\n".
        while line = @socket.gets("\n") do
          # Split line into words and unescape each word
          words = line.split.map! {|w| w.katcp_unescape!}
          # Handle requests, replies, and informs based on first character of
          # first word.
          case words[0][0,1]
          # Request
          when '?'
            # TODO Send 'unsupported' reply (or support requests from server?)
          # Reply
          when '!'
            # TODO: Raise exception if name is not same as @reqname?
            # TODO: Raise exception on non-ok?
            # Enqueue words to @rxq
            @rxq.enq(words)
          # Inform
          when '#'
            # If the name is same as @reqname
            if @reqname && @reqname == words[0][1..-1]
              # Enqueue words to @rxq
              @rxq.enq(words)
            else
              # Must be asynchronous inform message, add to list.
              line.katcp_unescape!
              line.chomp!
              @informs << line
            end
          else
            # Malformed line
            # TODO: Log error better?
            warn "malformed line: #{line.inspect}"
          end

        end # @socket.each_line block

        warn "Read on socket returned EOF"
        #TODO Close socket?  Push EOF flag into @rxq?
      end # Thread.new block
    end

    # TODO: Have a log_handler?

    # call-seq:
    #   request(name, *arguments) -> KATCP::Response
    #
    # Sends request +name+ with +arguments+ to server.  Returns KATCP::Response
    # object.
    #
    #   TODO: Raise exception if reply is not OK?
    def request(name, *arguments)
      # Massage name to allow Symbols and to allow '_' between words (since
      # that is more natural for Symbols) in place of '-'
      name = name.to_s.gsub('_','-')

      # Escape arguments
      arguments.map! {|arg| arg.to_s.katcp_escape}

      # Create response
      resp = Response.new

      # Get lock on @reqlock
      @reqlock.synchronize do
        # Store request name
        @reqname = name
        # Send request
        req = "?#{[name, *arguments].join(' ')}\n"
        @socket.print req
        # Loop on reply queue until done or error
        begin
          words = @rxq.deq
          resp << words
        end until words[0][0,1] == '!'
        # Clear request name
        @reqname = nil
      end
      resp
    end

    # call-seq:
    #   inform(clear=false) -> Array
    #
    # Returns Array of inform messages.  If +clear+ is +true+, clear messages.
    def informs(clear=false)
      msgs = @informs
      @informs = [] if clear
      msgs
    end

    # Translates calls to missing methods into KATCP requests.
    def method_missing(sym, *args)
      request(sym, *args)
    end

    # Provides terse string representation of +self+.
    def to_s
      s = "#{@remote_host}:#{@remote_port}"
    end

    # Provides more detailed String representation of +self+
    def inspect
      "#<#{self.class.name} #{to_s} (#{@informs.length} inform messages)>"
    end

    # call-seq:
    #   client_list -> KATCP::Response
    #
    # Issues a client_list request to the server.
    def client_list
      request(:client_list)
    end

    # call-seq:
    #   configure(*args) -> KATCP::Response
    #
    # Issues a configure request to the server.
    def configure(*args)
      request(:configure, *args)
    end

    # call-seq:
    #   halt -> KATCP::Response
    #
    # Issues a halt request to the server.  Shuts down the system.
    def halt
      request(:halt)
    end

    # call-seq:
    #   help -> KATCP::Response
    #   help(name) -> KATCP::Response
    #
    # Issues a help request to the server.  If +name+ is a Symbol, all '_'
    # characters are changed to '-'.  Response inform lines are sorted.
    def help(*args)
      # Change '_' to '-' in Symbol args
      args.map! do |arg|
        arg = arg.to_s.gsub('-', '_') if Symbol === arg
        arg
      end
      request(:help, *args).sort!
    end

    # call-seq:
    #   log_level -> KATCP::Response
    #   log_level(priority) -> KATCP::Response
    #
    # Query or set the minimum reported log priority.
    def log_level(*args)
      request(:log_level, *args)
    end

    # call-seq:
    #   mode -> KATCP::Response
    #   mode(new_mode) -> KATCP::Response
    #
    # Query or set the current mode.
    def mode(*args)
      request(:mode, *args)
    end

    # call-seq:
    #   restart -> KATCP::Response
    #
    # Issues a restart request to the server to restart the remote system.
    def restart
      request(:restart)
    end

    # call-seq:
    #   sensor_dump(*args) -> KATCP::Response
    #
    # Dumps the sensor tree.
    def sensor_dump(*args)
      request(:sensor_dump, *args)
    end

    # call-seq:
    #   sensor_list(*args) -> KATCP::Response
    #
    # Queries for list of available sensors.  Response inform lines are sorted.
    def sensor_list(*args)
      request(:sensor_list, *args).sort!
    end

    # call-seq:
    #   sensor_sampling(sensor) -> KATCP::Response
    #   sensor_sampling(sensor, strategy, *parameters) -> KATCP::Response
    #
    # Quesry or set sampling parameters for a sensor.
    def sensor_sampling(sensor, *args)
      request(:sensor_sampling, sensor, *args)
    end

    # call-seq:
    #   sensor_value(sensor) -> KATCP::Response
    #
    # Query a sensor.
    def sensor_value(sensor)
      request(:sensor_value, sensor)
    end

    # call-seq:
    #   watchdog -> KATCP::Response
    #
    # Issues a watchdog request to the server.
    def watchdog
      request(:watchdog)
    end

    alias :ping :watchdog

  end # class Client
end # module KATCP
