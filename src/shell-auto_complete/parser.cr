module Shell::AutoComplete
  module Parser
    # A flag spec matches either by name — the usual case, where *names* holds
    # every spelling the flag answers to — or by shape, where *pattern* matches
    # a whole token that is the flag and its value at once (`-20`, `+50`). A
    # pattern spec carries no names; capture group 1 of its pattern, or the
    # whole match when it has no groups, is the value handed to the flag.
    record FlagSpec,
      canonical : String,
      names : Array(String),
      takes_value : Bool,
      bool_value : Bool?,
      forced_value : String? = nil,
      pattern : Regex? = nil

    # The shapes a `bare_number:` flag accepts, keyed by {sign, keep_sign,
    # suffix}. Built here once rather than per parse call. Capture group 1 is
    # the value: `keep_sign` decides whether the sign travels with it (for a
    # signed flag, where `-20` means minus twenty rather than twenty), and
    # `suffix` lets a unit or scale follow the digits (`-123M`).
    BARE_NUMBER_PATTERNS = {
      {"minus", false, false} => /\A-(\d+)\z/,
      {"minus", true, false}  => /\A(-\d+)\z/,
      {"minus", false, true}  => /\A-(\d+\D*)\z/,
      {"minus", true, true}   => /\A(-\d+\D*)\z/,
      {"plus", false, false}  => /\A\+(\d+)\z/,
      {"plus", true, false}   => /\A(\+\d+)\z/,
      {"plus", false, true}   => /\A\+(\d+\D*)\z/,
      {"plus", true, true}    => /\A(\+\d+\D*)\z/,
      {"both", false, false}  => /\A[-+](\d+)\z/,
      {"both", true, false}   => /\A([-+]\d+)\z/,
      {"both", false, true}   => /\A[-+](\d+\D*)\z/,
      {"both", true, true}    => /\A([-+]\d+\D*)\z/,
    }

    # Returns the pattern for a `bare_number:` configuration.
    def self.bare_number_pattern(sign : String, keep_sign : Bool, suffix : Bool) : Regex
      BARE_NUMBER_PATTERNS[{sign, keep_sign, suffix}]
    end

    # When *dash_positionals* is true, a single-dash token that matches no flag
    # spec (e.g. `-foo`, or `-x` that isn't a short flag) is treated as a
    # positional rather than raising "unknown flag". This lets add/remove
    # positionals accept `-name` tokens alongside `+name`. Double-dash tokens
    # (`--name`) are still parsed strictly as flags so typos and `--help` keep
    # working; known flags always take precedence over a dash positional.
    # Every matched flag occurrence is also recorded, in command-line order, as
    # `{spelling as typed, raw value consumed}` — the spelling keeps its dashes
    # and is not canonicalized, and the value is `nil` when none was consumed
    # from argv (switches and forced-value shortcut flags).
    #
    # A token is resolved in one order, and only that order: an exact spelling,
    # then a pattern spec's shape, then a positional. So a declared flag is
    # never shadowed by a `bare_number:` pattern, and a bare number is never
    # swallowed by *dash_positionals*.
    def self.parse_argv(argv : Array(String), specs : Array(FlagSpec), dash_positionals : Bool = false) : NamedTuple(values: Hash(String, Array(String?)), positional: Array(String), occurrences: Array({String, String?}))
      values = {} of String => Array(String?)
      positional = [] of String
      occurrences = [] of {String, String?}
      pattern_specs = specs.select(&.pattern)
      index = 0
      while index < argv.size
        arg = argv[index]
        if arg == "--"
          positional.concat(argv[(index + 1)..])
          break
        end
        # Only a `--long` token splits on `=`; `-x=1` is looked up whole and so
        # matches nothing, exactly as before.
        if arg.starts_with?("--")
          name, eq, inline_value = arg.partition('=')
        else
          name, eq, inline_value = arg, "", ""
        end
        spec = specs.find(&.names.includes?(name))
        # A single-dash token is a flag only at two characters: `-xy` is not
        # bundled short flags here and never has been.
        spec = nil if spec && !arg.starts_with?("--") && arg.size != 2
        if spec
          values[spec.canonical] ||= [] of String?
          if spec.takes_value
            if eq == "="
              values[spec.canonical] << inline_value
              occurrences << {name, inline_value}
            else
              index += 1
              raise ParseError.new("flag #{name} requires a value") if index >= argv.size
              values[spec.canonical] << argv[index]
              occurrences << {name, argv[index]}
            end
          elsif forced = spec.forced_value
            values[spec.canonical] << forced
            occurrences << {name, nil}
          else
            values[spec.canonical] << spec.bool_value.to_s
            occurrences << {name, nil}
          end
        elsif matched = match_pattern(pattern_specs, arg)
          pattern_spec, pattern_value = matched
          values[pattern_spec.canonical] ||= [] of String?
          values[pattern_spec.canonical] << pattern_value
          occurrences << {arg, pattern_value}
        elsif arg.starts_with?("--")
          raise ParseError.new("unknown flag: #{name}")
        elsif arg.starts_with?("-") && arg.size > 1
          raise ParseError.new("unknown flag: #{arg}") unless dash_positionals
          positional << arg
        else
          positional << arg
        end
        index += 1
      end
      {values: values, positional: positional, occurrences: occurrences}
    end

    # The first pattern spec whose shape *arg* has, with the value it yields.
    # Declaration order decides between two patterns that both match.
    private def self.match_pattern(pattern_specs : Array(FlagSpec), arg : String) : {FlagSpec, String}?
      pattern_specs.each do |spec|
        if pattern = spec.pattern
          if match = pattern.match(arg)
            return {spec, match[1]? || match[0]}
          end
        end
      end
      nil
    end
  end
end
