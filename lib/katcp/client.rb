require 'monitor'
require 'socket'

require 'katcp/util'

# Holds KATCP related classes etc.
module KATCP

  # Class that holds response to request
  # Bascially like an Array with each element representing a line of the
  # server's response.  Each "line" is stored as an Array (of Strings) whose
  # elements are the decoded "words" (which may contain embedded spaces) of the
  # reply.
  class Response
    def initialize
      @lines = []
    end

    def <<(line)
      @lines << line
    end

    def length
      @lines.length
    end

    def [](*args)
      @lines[*args]
    end

    def complete?
      # Last line, first word, first character
      @lines[-1] && @lines[-1][0][0,1] == '!'
    end

    # Rejoins words into lines and lines into one String
    def to_s
      @lines.map do |line|
        line.join(' ')
      end.join("\n")
    end

    def inspect
      s = "#<KATCP::Response:0x#{object_id.to_s(16)}>("
      if complete? && @lines.length > 1
        s += "#{length-1} lines)"
      elif !complete?
        s += "#{length} lines, incomplete)"
      end
    end
  end

  # Facilitates talking to a KATCP server.
  class Client
    # Creates a KATCP client that connects to a KATCP server at +remote_host+
    # on +remote_port+.  If local_host and local_port are specified, then those
    # parameters are used on the local end to establish the connection.
    def initialize(remote_host, remote_port=7147, local_host=nil, local_port=nil)

      # Save remote_host and remote_port for #inspect
      @remote_host = remote_host
      @remote_port = remote_port

      # @socket is the socket connecting to the KATCP server
      @socket = TCPSocket.new(remote_host, remote_port, local_host, local_port)

      # Init attribute(s)
      @inform_handler = STDERR

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
          # Split line into words and decode each word
          words = line.split.map! {|w| w.decode_katcp!}
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
              # Must be asynchronous inform message
              @inform_handler << line.decode_katcp! if @inform_handler
            end
          else
            # Malformed line
            # TODO: Log error bettero?
            STDERR.puts "malformed line: #{line.inspect}"
          end

        end # @socket.each_line block

        warn "Read on socket returned EOF"
        #TODO Close socket?  Push EOF flag into @rxq?
      end # Thread.new block
    end

    # @inform_handler is an object for handling asynchronous "inform" messages.
    # The inform_handler must support the #<< insertion operator.
    # If nil, all asynchronous "inform" messages are dropped.
    # Defaults to STDERR.
    # TODO: Pass un-decoded katcp String?
    # TODO: Make this be a Proc object (or at least support it)?
    attr :inform_handler

    # TODO: Have a separate log_handler?

    # Sends request +name+ with +arguments+ to server.  Returns KATCP::Response
    # object.
    #
    # TODO: Return reply as well or just raise exception if reply is not OK?
    def request(name, *arguments)
      # Encode name to allow Symbols and to allow _ between words (since that
      # is more natural for Symbols)
      name = name.to_s.gsub('_','-')
      # Encode arguments
      arguments.map! {|arg| arg.to_s.encode_katcp}

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

    # Translates calls to mising methods into KATCP requests
    def method_missing(sym, *args)
      request(sym, *args)
    end

    # Provides terse representation
    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)}>(#{@remote_host}:#{@remote_port})"
    end

  end # class Client
end # module KATCP
