# :nodoc:
struct Enum
  def self.__arg_transform(value : String, **opts) : self
    # Handle comma-separated values for @[Flags] enums (e.g. "read,write").
    parts = value.split(',')
    if parts.size == 1
      __arg_member(value)
    else
      result = __arg_member(parts[0].strip)
      parts[1..].each do |part|
        result = new(result.value | __arg_member(part.strip).value)
      end
      result
    end
  end

  # One member by name — any case, `-` or `_` between words (`Enum.parse` is
  # case-insensitive; hyphens are normalized to underscores first). A name that
  # matches nothing raises with the allowed values, in the wording `choices:`
  # uses, rather than the enum's Crystal type name.
  private def self.__arg_member(value : String) : self
    parse(value.tr("-", "_"))
  rescue ArgumentError
    raise ArgumentError.new("#{value} is not one of #{__arg_choices.join(", ")}")
  end

  # The member names as the shell sees them: kebab-case, aliases collapsed.
  # uniq: alias constants (KB = 1024, Kb = 1024) kebab-case to the same
  # candidate; offer it once.
  def self.__arg_choices : Array(String)
    names.map(&.to_s.underscore.tr("_", "-")).uniq!
  end

  def self.__arg_complete(prefix : String, **opts) : Array(String)
    __arg_choices
  end
end
