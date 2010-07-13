require 'monitor'
require 'socket'

require 'katcp/util'

# Holds KATCP related classes etc.
module KATCP

  # Class that holds response to request.  Bascially like an Array with each
  # element representing a line of the server's response.  Each "line" is
  # stored as an Array (of Strings) whose elements are the decoded "words"
  # (which may contain embedded spaces) of the reply.
  class Response

    # Default inspect_mode for new Response objects.  When running in IRB,
    # default is :to_s, otherwise, default is nil.
    @@inspect_mode = (defined?(IRB) ? :to_s : nil)

    # Returns default inspect mode for new Response objects.
    def self.inspect_mode
      @@inspect_mode
    end

    # Sets default inspect mode for new Response objects.
    def self.inspect_mode=(mode)
      @@inspect_mode = mode
    end

    # Inspect mode for +self+. +nil+ or <tt>:inspect</tt> means terse form.
    # Other symbol (typically <tt>:to_s</tt>) means call that method
    attr :inspect_mode

    # Creates a new Response object with given inspect_mode and lines Array
    def initialize(inspect_mode=@@inspect_mode, lines=[])
      raise TypeError.new('lines must be an Array') unless Array === lines
      @lines = lines
      @inspect_mode = inspect_mode
    end

    # Returns a deep copy of self
    def dup
      self.class.new(@inspect_mode, @lines.map {|words| words.map {|word| word.dup}})
    end

    # Pushes +line+ onto +self+.  +line+ must be an Array of words (each of
    # which may contain embedded spaces).
    def <<(line)
      raise TypeError.new('expected Array') unless Array === line
      @lines << line
    end

    # Returns number of lines in +self+ including all inform lines and the
    # reply line, if present.
    def length
      @lines.length
    end

    # Returns subset of lines.  Similar to Array#[].
    def [](*args)
      @lines[*args]
    end

    # Returns name of request corresponding to +self+ if complete, otherwise
    # nil.
    def reqname
      # All but first character of first word of last line, if complete
      @lines[-1][0][1..-1] if complete?
    end

    # Returns true if at least one line exists and the most recently added line
    # is a reply line.
    def complete?
      # If at least one line exists, return true if last line, first word, first
      # character is '!'.
      @lines[-1] && @lines[-1][0][0,1] == '!'
    end

    # Returns status from reply line if complete, otherwise
    # <tt>'incomplete'</tt>.
    #
    #   TODO: Return nil if incomplete?
    def status
      complete? ? @lines[-1][1] : 'incomplete'
    end

    # Sorts the list of inform lines in-place and returns +self+
    def sort!
      n = complete? ? length-1 : length
      @lines[0,n] = @lines[0,n].sort if n > 0
      self
    end

    # Returns a copy of +self+ with inform lines sorted
    def sort
      dup.sort!
    end

    # Rejoins words into lines and lines into one String
    def to_s
      @lines.map do |line|
        line.join(' ')
      end.join("\n")
    end

    # Provides a terse (or not so terse) summary of +self+ depending on value
    # of +mode+.
    def inspect(mode=@inspect_mode)
      if mode && mode != :inspect?
        send(mode) rescue inspect(nil)
      else
        s = "#<KATCP::Response:0x#{object_id.to_s(16)}> "
        if complete?
          s += "#{status}"
          if @lines.length > 1
            s += ", #{length-1} lines"
          end
        else
          s += "#{length} lines, incomplete"
        end
      end
    end
  end

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

    # object for handling asynchronous "inform" messages.  The inform_handler
    # must support the <tt><<</tt> insertion operator.  If nil, all
    # asynchronous "inform" messages are dropped.  Defaults to STDERR.
    #
    #   TODO: Pass un-decoded katcp String?
    #   TODO: Make this be a Proc object (or at least support it)?
    attr :inform_handler

    # TODO: Have a separate log_handler?

    # Sends request +name+ with +arguments+ to server.  Returns KATCP::Response
    # object.
    #
    #   TODO: Return reply as well or just raise exception if reply is not OK?
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

    # Define #help explicitly so output can be sorted.
    def help(*args)
      request(:help, *args).sort!
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
      "#<#{self.class.name}:0x#{object_id.to_s(16)} #{to_s}>"
    end

  end # class Client
end # module KATCP
