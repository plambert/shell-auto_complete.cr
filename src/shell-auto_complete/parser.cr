module Shell::AutoComplete
  module Parser
    record FlagSpec,
      canonical : String,
      names : Array(String),
      takes_value : Bool,
      bool_value : Bool?,
      forced_value : String? = nil

    def self.parse_argv(argv : Array(String), specs : Array(FlagSpec)) : NamedTuple(values: Hash(String, String?), positional: Array(String))
      values = {} of String => String?
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
          if spec.takes_value
            if eq == "="
              values[spec.canonical] = inline_value
            else
              index += 1
              raise ParseError.new("flag #{name} requires a value") if index >= argv.size
              values[spec.canonical] = argv[index]
            end
          elsif fv = spec.forced_value
            values[spec.canonical] = fv
          else
            values[spec.canonical] = spec.bool_value.to_s
          end
        elsif arg.starts_with?("-") && arg.size == 2
          spec = specs.find(&.names.includes?(arg))
          raise ParseError.new("unknown flag: #{arg}") unless spec
          if spec.takes_value
            index += 1
            raise ParseError.new("flag #{arg} requires a value") if index >= argv.size
            values[spec.canonical] = argv[index]
          elsif fv = spec.forced_value
            values[spec.canonical] = fv
          else
            values[spec.canonical] = spec.bool_value.to_s
          end
        elsif arg.starts_with?("-") && arg.size > 2
          raise ParseError.new("unknown flag: #{arg}")
        else
          positional << arg
        end
        index += 1
      end
      {values: values, positional: positional}
    end
  end
end
