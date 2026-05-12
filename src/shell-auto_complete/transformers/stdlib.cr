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

struct Socket::IPAddress
  def self.__arg_transform(value : String, **opts) : Socket::IPAddress
    if colon_index = value.rindex(':')
      host = value[0, colon_index]
      port_str = value[colon_index + 1..]
      port = port_str.to_i32? || raise ArgumentError.new("invalid port in #{value.inspect}: #{port_str.inspect}")
      Socket::IPAddress.new(host, port)
    else
      Socket::IPAddress.new(value, 0)
    end
  end
end
