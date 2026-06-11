module Shell::AutoComplete
  module Parser
    record FlagSpec,
      canonical : String,
      names : Array(String),
      takes_value : Bool,
      bool_value : Bool?,
      forced_value : String? = nil

    # When *dash_positionals* is true, a single-dash token that matches no flag
    # spec (e.g. `-foo`, or `-x` that isn't a short flag) is treated as a
    # positional rather than raising "unknown flag". This lets add/remove
    # positionals accept `-name` tokens alongside `+name`. Double-dash tokens
    # (`--name`) are still parsed strictly as flags so typos and `--help` keep
    # working; known flags always take precedence over a dash positional.
    def self.parse_argv(argv : Array(String), specs : Array(FlagSpec), dash_positionals : Bool = false) : NamedTuple(values: Hash(String, Array(String?)), positional: Array(String))
      values = {} of String => Array(String?)
      positional = [] of String
      index = 0
      while index < argv.size
        arg = argv[index]
        if arg == "--"
          positional.concat(argv[(index + 1)..])
          break
        end
        if arg.starts_with?("--")
          name, eq, inline_value = arg.partition('=')
          spec = specs.find(&.names.includes?(name))
          unless spec
            raise ParseError.new("unknown flag: #{name}")
          end
          values[spec.canonical] ||= [] of String?
          if spec.takes_value
            if eq == "="
              values[spec.canonical] << inline_value
            else
              index += 1
              raise ParseError.new("flag #{name} requires a value") if index >= argv.size
              values[spec.canonical] << argv[index]
            end
          elsif fv = spec.forced_value
            values[spec.canonical] << fv
          else
            values[spec.canonical] << spec.bool_value.to_s
          end
        elsif arg.starts_with?("-") && arg.size == 2
          spec = specs.find(&.names.includes?(arg))
          if spec.nil?
            raise ParseError.new("unknown flag: #{arg}") unless dash_positionals
            positional << arg
          else
            values[spec.canonical] ||= [] of String?
            if spec.takes_value
              index += 1
              raise ParseError.new("flag #{arg} requires a value") if index >= argv.size
              values[spec.canonical] << argv[index]
            elsif fv = spec.forced_value
              values[spec.canonical] << fv
            else
              values[spec.canonical] << spec.bool_value.to_s
            end
          end
        elsif arg.starts_with?("-") && arg.size > 2
          raise ParseError.new("unknown flag: #{arg}") unless dash_positionals
          positional << arg
        else
          positional << arg
        end
        index += 1
      end
      {values: values, positional: positional}
    end
  end
end
