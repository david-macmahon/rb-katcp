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

    # Sends request +name+ with +arguments+ to server.  Returns KATCP::Response
    # object.
    #
    #   TODO: Return reply as well or just raise exception if reply is not OK?
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

    # Issues a client_list request to the server.
    def client_list(*args)
      request(:client_list, *args)
    end

    # Issues a configure request to the server.
    def configure(*args)
      request(:configure, *args)
    end

    # Issues a halt request to the server.
    def halt(*args)
      request(:halt, *args)
    end

    # Issues a help request to the server.  Response inform lines are sorted.
    def help(*args)
      request(:help, *args).sort!
    end

    # Issues a log_level request to the server.
    def log_level(*args)
      request(:log_level, *args)
    end

    # Issues a mode request to the server.
    def mode(*args)
      request(:mode, *args)
    end

    # Issues a restart request to the server.
    def restart(*args)
      request(:restart, *args)
    end

    # Issues a sensor_list request to the server.  Response inform lines are
    # sorted.
    def sensor_list(*args)
      request(:sensor_list, *args).sort!
    end

    # Issues a sensor_sampling request to the server.
    def sensor_sampling(*args)
      request(:sensor_sampling, *args)
    end

    # Issues a sensor_value request to the server.  Response inform lines are
    # sorted.
    def sensor_value(*args)
      request(:sensor_value, *args).sort!
    end

    # Issues a watchdog request to the server.
    def watchdog(*args)
      request(:watchdog, *args)
    end

    alias :ping :watchdog

  end # class Client
end # module KATCP
