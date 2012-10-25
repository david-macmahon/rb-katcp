require 'rubygems'
require 'thread'
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

      # Save parameters
      @remote_host = remote_host.to_s
      @remote_port = remote_port
      @local_host = local_host
      @local_port = local_port

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

      # Timeout value for socket operations
      @socket_timeout = 0.25

      # Try to connect socket and start listener thread, but don't worry if it
      # fails (each request attempt will try to reconnect if needed)
      connect rescue nil
    end

    # Connect socket and start listener thread
    def connect
      # Close existing connection (if any)
      close

      # Create new socket.  Times out in 3 seconds if not happy.
      @socket = TCPSocket.new(@remote_host, @remote_port, @local_host, @local_port)

      # Start thread that reads data from server.
      Thread.new do
        catch :giveup do
          while true
            begin
              req_timeouts = 0
              while req_timeouts < 2
                # Use select to wait with timeout for data or error
                rd_wr_err = select([@socket], [], [@socket], @socket_timeout)

                # Handle timeout
                if rd_wr_err.nil?
                  # Timeout, increment req_timeout if we're expecting a reply,
                  # then try again
                  req_timeouts += 1 if @reqname
                  next
                end

                # Handle error
                if rd_wr_err[2][0]
                  # Ignore unless we're expected a reply
                  next unless @reqname
                  # Otherwise, send double-bang error response, and give up
                  @rxq.enq(['!!socket-error'])
                  throw :giveup
                end

                # OK to read!

                # TODO: Monkey-patch gets so that it recognizes "\r" or "\n" as
                # line endings.  Currently only recognizes fixed strings, so for
                # now go with "\n".
                line = @socket.gets("\n")

                # If EOF
                if line.nil?
                  # Send double-bang error response, and give up
                  @rxq.enq(['!!socket-eof'])
                  throw :giveup
                end

                # Split line into words and unescape each word
                words = line.chomp.split(/[ \t]+/).map! {|w| w.katcp_unescape!}
                # Handle requests, replies, and informs based on first character
                # of first word.
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
                end # case words[0][0,1]

                # Reset req_timeouts counter
                req_timeouts = 0

              end # while req_timeouts < 2

              # Got 2 timeouts in a request!
              # Send double-bang timeout response
              @rxq.enq(['!!socket-timeout'])
              throw :giveup

            rescue Exception => e
              $stderr.puts e; $stderr.flush
            end # begin
          end # while true
        end # catch :giveup
      end # Thread.new block

    end #connect

    # Close socket if it exists and is not already closed.  Subclasses can
    # override #close to perform additional cleanup as needed, but they must
    # either close the socket themselves or call super.
    def close
      @socket.close if @socket && !@socket.closed?
    end

    # Return remote hostname
    def host
      @remote_host
    end

    # Return remote port
    def port
      @remote_port
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
      # (Re-)connect if @socket is in an invalid state
      connect if @socket.nil? || @socket.closed?

      # Massage name to allow Symbols and to allow '_' between words (since
      # that is more natural for Symbols) in place of '-'
      reqname = name.to_s.gsub('_','-')

      # Escape arguments
      reqargs = arguments.map! {|arg| arg.to_s.katcp_escape}

      # TODO Find a more elegant way to code this retry loop?
      attempts = 0
      while true
        attempts += 1

        # Create response
        resp = Response.new

        # Give "words" scope outside of synchronize block
        words = nil

        # Get lock on @reqlock
        @reqlock.synchronize do
          # Store request name
          @reqname = reqname
          # Send request
          req = "?#{[reqname, *reqargs].join(' ')}\n"
          @socket.print req
          # Loop on reply queue until done or error
          begin
            words = @rxq.deq
            resp << words
          end until words[0][0,1] == '!'
          # Clear request name
          @reqname = nil
        end # @reqlock.synchronize

        # Break out of retry loop unless double-bang reply
        break unless words[0][0,2] == '!!'

        # Double-bang reply!!

        # If we've already attempted more than once (i.e. twice)
        if attempts > 1
          # Raise exception
          case words[0]
          when '!!socket-timeout'; raise TimeoutError.new(resp)
          when '!!socket-error'; raise SocketError.new(resp)
          when '!!socket-eof'; raise SocketEOF.new(resp)
          else raise RuntimeError.new(resp)
          end
        end

        # Reconnect and try again
        connect
      end # while true

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
    # Raises an exception if the response status is not OK.
    def method_missing(sym, *args)
      resp = request(sym, *args)
      raise resp.to_s unless resp.ok?
      resp
    end

    # Provides terse string representation of +self+.
    def to_s
      "#{@remote_host}:#{@remote_port}"
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
