# :nodoc:
struct Char
  def self.__arg_transform(value : String, **opts) : Char
    raise ArgumentError.new("expected single character, got #{value.size}: #{value.inspect}") unless value.size == 1
    value.char_at(0)
  end
end
