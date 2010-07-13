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
end
