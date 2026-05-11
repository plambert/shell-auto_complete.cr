require "uri"
require "log"
require "socket"

class URI
  def self.__arg_transform(value : String, **opts) : URI
    URI.parse(value)
  end
end

struct Time
  def self.__arg_transform(value : String, **opts) : Time
    # Try ISO 8601 / RFC 3339 first (most common CLI input)
    begin
      return Time.parse_iso8601(value)
    rescue
    end

    # Try RFC 2822
    begin
      return Time::Format::RFC_2822.parse(value)
    rescue
    end

    raise ArgumentError.new("unrecognized time format: #{value}")
  end
end

enum ::Log::Severity
  def self.__arg_transform(value : String, **opts) : ::Log::Severity
    parse(value.tr("-", "_"))
  end
end

class Regex
  def self.__arg_transform(value : String, **opts) : Regex
    Regex.new(value)
  end
end
