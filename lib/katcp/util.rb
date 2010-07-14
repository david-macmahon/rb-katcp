require 'narray'

#TODO: Create ntoh! (etc) methods for narray

# String add-ons for KATCP
class String
  # In-place encodes +self+ into KATCP format.  Always returns +self+.
  def encode_katcp!
    empty? ? self[0..-1] = '\@' : self.gsub!(/[\\ \0\n\r\e\t]/) do |s|
      case s
      when "\\": '\\'
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

  # Encodes +self+ into KATCP format and returns new String.
  def encode_katcp
    dup.encode_katcp!
  end
  
  # In-place decodes +self+ from KATCP format.  Always returns +self+.
  def decode_katcp!
    self == '\@' ? self[0..-1] = '' : self.gsub!(/\\[\\_0nret]/) do |s|
      case s
      when '\\': "\\"
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

  # Decodes +self+ from KATCP format and returns new String.
  def decode_katcp
    dup.decode_katcp!
  end

  # call-seq:
  #   to_na(typecode[,size,...][,byteswap=:ntoh]) -> NArray
  #
  # Convert String to NArray accoring to +typecode+ and call byte swap method
  # given by Symbol +byteswap+.  Pass +nil+ for +byteswap+ to skip the byte
  # swap conversion.
  #
  # Because, as of this writing, KATCP servers typically run on big endian
  # systems which return binary payload data in network byte order, the default
  # for byteswap is <tt>:ntoh</tt>, which converts from network byte order to
  # host (i.e. native) order.
  def to_na(typecode, *args)
    # Default to :ntoh
    byteswap = :ntoh
    if !args.empty? && (Symbol === args[-1] || args[-1].nil?)
      byteswap = args.pop
    end
    na = NArray.to_na(self, typecode, *args)
    na = na.send(byteswap) if byteswap
    na
  end
end
