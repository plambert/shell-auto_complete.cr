class Array(T)
  def self.__arg_transform(value : String, **opts) : Array(T)
    delim = opts[:delimiter]?
    # delimiter: nil means no splitting; default delimiter is ","
    if delim.nil? && !opts.has_key?(:delimiter)
      parts = value.split(",")
    elsif delim.is_a?(String)
      parts = value.split(delim)
    else
      parts = [value]
    end
    parts.map { |part| T.__arg_transform(part, **opts).as(T) }
  end
end

struct Set(T)
  def self.__arg_transform(value : String, **opts) : Set(T)
    delim = opts[:delimiter]?
    if delim.nil? && !opts.has_key?(:delimiter)
      parts = value.split(",")
    elsif delim.is_a?(String)
      parts = value.split(delim)
    else
      parts = [value]
    end
    result = Set(T).new
    parts.each do |raw|
      result.add(T.__arg_transform(raw, **opts).as(T))
    end
    result
  end
end
