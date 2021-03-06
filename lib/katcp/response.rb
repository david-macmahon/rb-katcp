require 'katcp/util'
require 'katcp/version'

# Holds KATCP related classes etc.
module KATCP

  # Class that holds response to request.  Bascially like an Array with each
  # element representing a line of the server's response.  Each "line" is
  # stored as an Array (of Strings) whose elements are the unescaped "words"
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
    def initialize(inspect_mode=@@inspect_mode, lines_array=[])
      raise TypeError.new('lines must be an Array') unless Array === lines_array
      @lines = lines_array
      @inspect_mode = inspect_mode
    end

    # call-seq:
    #   lines -> Array of Arrays
    #
    # Returns a copy contained lines.  Each line is itself an Array of words.
    def lines
      @lines.map {|words| words.map {|word| word.dup}}
    end

    # call-seq:
    #   grep(pattern, join=' ') -> Array or Strings
    #   grep(pattern, nil) -> Array of Arrays
    #   grep(pattern, join=' ') {|line_array| ...} -> Array of Strings
    #   grep(pattern, nil) {|line_array| ...} -> Array of ...
    #
    # Greps through lines for +pattern+.  If a block is given, each line will
    # be passed to the block and replaced in the returned Array by the block's
    # return value.  If +join+ is non-nil (default is a space character), then
    # each element of the returned Array (i.e. each line) will have its
    # elements (i.e. words) joined together using +join+ as a delimiter.
    def grep(pattern, join=' ', &block)
      matches = @lines.find_all {|l| !l.grep(pattern).empty?}
      matches.map!(&block) if block_given?
      matches.map! {|l| l.join(join)} if join
      matches
    end

    # call-seq:
    #   dup -> KATCP::Response
    #
    # Returns a deep copy of self
    def dup
      self.class.new(@inspect_mode, lines)
    end

    # Pushes +line+ onto +self+.  +line+ must be an Array of words (each of
    # which may contain embedded spaces).
    def <<(line)
      raise TypeError.new('expected Array') unless Array === line
      @lines << line
    end

    # call-seq:
    #   length -> Integer
    #
    # Returns number of lines in +self+ including all inform lines and the
    # reply line, if present.
    def length
      @lines.length
    end

    # call-seq:
    #   response[index] -> Array or nil
    #   response[start, length] -> Array_of_Arrays or nil
    #   response[range] -> Array_of_Arrays or nil
    #
    # Returns subset of lines.  Similar to Array#[].
    def [](*args)
      @lines[*args]
    end

    # call-seq:
    #   reqname -> String
    #
    # Returns name of request corresponding to +self+ if complete, otherwise
    # nil.
    def reqname
      # All but first character of first word of last line, if complete
      @lines[-1][0][1..-1] if complete?
    end

    # call-seq:
    #   complete? -> true_or_false
    #
    # Returns true if at least one line exists and the most recently added line
    # is a reply line.
    def complete?
      # If at least one line exists, return true if last line, first word, first
      # character is '!'.
      @lines[-1] && @lines[-1][0][0,1] == '!'
    end

    # call-seq:
    #   status -> String
    #
    # Returns status from reply line if complete, otherwise
    # <tt>'incomplete'</tt>.
    def status
      complete? ? @lines[-1][1] : 'incomplete'
    end

    # call-seq:
    #   ok? -> true_or_false
    #
    # Returns true if status is <tt>'ok'</tt>.
    def ok?
      'ok' == status
    end

    # call-seq:
    #   sort! -> self
    #
    # Sorts the list of inform lines in-place and returns +self+
    def sort!
      n = complete? ? length-1 : length
      @lines[0,n] = @lines[0,n].sort if n > 0
      self
    end

    # call-seq:
    #   sort -> KATCP::Response
    #
    # Returns a copy of +self+ with inform lines sorted
    def sort
      dup.sort!
    end

    # call-seq:
    #   to_s -> String
    #
    # Rejoins words into lines and lines into one String
    def to_s
      @lines.map do |line|
        line.join(' ')
      end.join("\n")
    end

    # call-seq:
    #   payload -> String
    #
    # Returns contents of reply line ("words" joined by spaces) after status
    # word if <tt>ok?</tt> returns true.  Returns an empty string if
    # <tt>ok?</tt> is false or no payload exists.
    def payload
      ok? ? @lines[-1][2..-1].join(' ') : ''
    end

    # call-seq:
    #   inspect -> String
    #   inspect(mode) -> String
    #
    # Provides a terse (or not so terse) summary of +self+ depending on value
    # of +mode+.  If given, +mode+ will be treated as inspect_mode.
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
  end # class Response
end # module KATCP
