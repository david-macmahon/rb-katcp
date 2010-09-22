require 'narray'

#TODO: Create ntoh! (etc) methods for narray

# String add-ons for KATCP
class String
  # In-place escapes +self+ into KATCP format.  Always returns +self+.
  def katcp_escape!
    empty? ? self[0..-1] = '\@' : self.gsub!(/[\\ \0\n\r\e\t]/) do |s|
      case s
      when "\\": '\\\\'
      when " " : '\_'
      when "\0": '\0'
      when "\n": '\n'
      when "\r": '\r'
      when "\e": '\e'
      when "\t": '\t'
      end
    end
    self
  end

  # Escapes +self+ into KATCP format and returns new String.
  def katcp_escape
    dup.katcp_escape!
  end
  
  # In-place unescapes +self+ from KATCP format.  Always returns +self+.
  def katcp_unescape!
    self == '\@' ? self[0..-1] = '' : self.gsub!(/\\[\\_0nret]/) do |s|
      case s
      when '\\\\': "\\"
      when '\_': " "
      when '\0': "\0"
      when '\n': "\n"
      when '\r': "\r"
      when '\e': "\e"
      when '\t': "\t"
      end
    end
    self
  end

  # Unescapes +self+ from KATCP format and returns new String.
  def katcp_unescape
    dup.katcp_unescape!
  end

  # call-seq:
  #   to_na(typecode) -> NArray
  #   to_na(typecode, size[, ...]) -> NArray
  #
  # Convert String to NArray accoring to +typecode+.
  def to_na(typecode, *args)
    NArray.to_na(self, typecode, *args)
  end
end
