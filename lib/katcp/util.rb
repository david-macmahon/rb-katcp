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
  # given by Symbol +byteswap+.
  def to_na(typecode, *args)
    byteswap = (Symbol === args[-1]) ? args.pop : :ntoh
    na = NArray.to_na(self, typecode, *args)
    na = na.send(byteswap) if byteswap
    na
  end
end
