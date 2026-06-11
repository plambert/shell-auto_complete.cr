module Shell::AutoComplete::Types
  # A set delta parsed from `+name` / `-name` / bare `name` tokens, used as the
  # type of a variadic positional:
  #
  #     positionals changes : Shell::AutoComplete::Types::SetDelta, "features to toggle"
  #
  # Each token is parsed into a single-entry `Hash(String, Bool)` — `+name` and a
  # bare `name` map to `true` (add), `-name` maps to `false` (remove) — and the
  # per-token results are merged into one `Hash(String, Bool)` (last write wins on
  # a repeated key), which is what the positional binds to. Apply the delta to an
  # existing `Set(String)` with `.apply`.
  module SetDelta
    # Parse one `+name` / `-name` / `name` token into `{name => bool}`.
    def self.__arg_transform(value : String, **opts) : Hash(String, Bool)
      case value[0]?
      when '+'
        key = value[1..]
        add = true
      when '-'
        key = value[1..]
        add = false
      else
        key = value
        add = true
      end
      raise ArgumentError.new("empty set-delta token: #{value.inspect}") if key.empty?
      {key => add}
    end

    # Apply *delta* to *set* in place: keys mapped to `true` are added, keys
    # mapped to `false` are removed. Returns the same set for chaining.
    def self.apply(set : Set(String), delta : Hash(String, Bool)) : Set(String)
      delta.each do |key, add|
        if add
          set << key
        else
          set.delete(key)
        end
      end
      set
    end
  end
end
