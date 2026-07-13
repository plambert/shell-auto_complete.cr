# :nodoc:
struct Enum
  def self.__arg_transform(value : String, **opts) : self
    # Handle comma-separated values for @[Flags] enums (e.g. "read,write").
    # Normalize hyphens to underscores for kebab-case support.
    # Enum.parse is case-insensitive.
    parts = value.split(',')
    if parts.size == 1
      parse(value.tr("-", "_"))
    else
      result = parse(parts[0].strip.tr("-", "_"))
      parts[1..].each do |part|
        result = new(result.value | parse(part.strip.tr("-", "_")).value)
      end
      result
    end
  end

  def self.__arg_complete(prefix : String, **opts) : Array(String)
    # uniq: alias constants (KB = 1024, Kb = 1024) kebab-case to the same
    # candidate; offer it once.
    names.map(&.to_s.underscore.tr("_", "-")).uniq
  end
end
