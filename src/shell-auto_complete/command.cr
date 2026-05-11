module Shell::AutoComplete
  abstract class Command
    record FlagInfo,
      canonical : String,
      aliases : Array(String),
      short : String?,
      description : String

    macro inherited
      def self.command_name : String
        {% ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        {% if ann && ann[:name] %}
          {{ ann[:name] }}
        {% else %}
          File.basename(PROGRAM_NAME)
        {% end %}
      end

      def self.flag_info(ivar_name : String) : ::Shell::AutoComplete::Command::FlagInfo
        \{% for ivar in @type.instance_vars %}
          \{% if fann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
            if ivar_name == \{{ivar.name.stringify}}
              return ::Shell::AutoComplete::Command::FlagInfo.new(
                canonical: \{{fann[:canonical]}},
                aliases: \{{fann[:aliases]}},
                short: \{{fann[:short]}},
                description: \{{fann[:description]}},
              )
            end
          \{% end %}
        \{% end %}
        raise "no flag named \#{ivar_name}"
      end

      def self.parse(argv : Array(String)) : self
        specs = [] of ::Shell::AutoComplete::Parser::FlagSpec
        \{% for ivar in @type.instance_vars %}
          \{% if fann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
            \{% if ivar.type.id.stringify == "Bool" %}
              pos_names_\{{ivar.name}} = [\{{fann[:canonical]}}] of String
              \{% if fann[:short] %}
                pos_names_\{{ivar.name}} << \{{fann[:short]}}
              \{% end %}
              specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
                canonical: \{{fann[:canonical]}},
                names: pos_names_\{{ivar.name}},
                takes_value: false,
                bool_value: true,
              )
              \{% if fann[:negatable] %}
                negative_name = "--no-" + \{{fann[:canonical]}}.gsub(/^--/, "")
                specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
                  canonical: \{{fann[:canonical]}},
                  names: [negative_name],
                  takes_value: false,
                  bool_value: false,
                )
              \{% end %}
            \{% else %}
              names_\{{ivar.name}} = [\{{fann[:canonical]}}] of String
              \{% for alias_name in fann[:aliases] %}
                names_\{{ivar.name}} << \{{alias_name}}
              \{% end %}
              \{% if fann[:short] %}
                names_\{{ivar.name}} << \{{fann[:short]}}
              \{% end %}
              specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
                canonical: \{{fann[:canonical]}},
                names: names_\{{ivar.name}},
                takes_value: true,
                bool_value: nil,
              )
            \{% end %}
          \{% end %}
        \{% end %}
        result = ::Shell::AutoComplete::Parser.parse_argv(argv, specs)
        inst = new
        \{% for ivar in @type.instance_vars %}
          \{% if fann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
            \{% if ivar.type.id.stringify == "Bool" %}
              if v = result[:values][\{{fann[:canonical]}}]?
                inst.\{{ivar.name}} = (v == "true")
              end
            \{% else %}
              if v = result[:values][\{{fann[:canonical]}}]?
                \{% if tw = fann[:transform_with] %}
                  transformed_value = self.\{{tw.id}}(v)
                \{% else %}
                  \{% inner_type = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                  transformed_value = \{{inner_type}}.__arg_transform(v)
                \{% end %}
                inst.\{{ivar.name}} = transformed_value
                \{% inner_type_v = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                \{% if vw = fann[:validate_with] %}
                  result_v = self.\{{vw.id}}(transformed_value)
                \{% elsif inner_type_v.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                  result_v = \{{inner_type_v}}.__arg_validate(transformed_value, **\{{fann[:forwarded_opts]}})
                \{% else %}
                  result_v = true
                \{% end %}
                case result_v
                when true
                  # ok
                when String
                  raise ::Shell::AutoComplete::ParseError.new(result_v.as(String))
                when false
                  raise ::Shell::AutoComplete::ParseError.new("not a valid \{{ivar.name}}")
                end
              end
            \{% end %}
          \{% end %}
        \{% end %}
        positional_tokens = result[:positional]
        pos_index = 0
        \{% for ivar in @type.instance_vars %}
          \{% if pann = ivar.annotation(::Shell::AutoComplete::PositionalDef) %}
            if pos_index < positional_tokens.size
              raw_pos_\{{ivar.name}} = positional_tokens[pos_index]
              \{% if tw = pann[:transform_with] %}
                transformed_pos_\{{ivar.name}} = self.\{{tw.id}}(raw_pos_\{{ivar.name}})
              \{% else %}
                \{% pos_inner_type = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                transformed_pos_\{{ivar.name}} = \{{pos_inner_type}}.__arg_transform(raw_pos_\{{ivar.name}})
              \{% end %}
              inst.\{{ivar.name}} = transformed_pos_\{{ivar.name}}
              \{% if vw = pann[:validate_with] %}
                result_v_pos_\{{ivar.name}} = self.\{{vw.id}}(transformed_pos_\{{ivar.name}})
              \{% else %}
                \{% pos_inner_type_v = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                \{% if pos_inner_type_v.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                  result_v_pos_\{{ivar.name}} = \{{pos_inner_type_v}}.__arg_validate(transformed_pos_\{{ivar.name}}, **\{{pann[:forwarded_opts]}})
                \{% else %}
                  result_v_pos_\{{ivar.name}} = true
                \{% end %}
              \{% end %}
              case result_v_pos_\{{ivar.name}}
              when true
                # ok
              when String
                raise ::Shell::AutoComplete::ParseError.new(result_v_pos_\{{ivar.name}}.as(String))
              when false
                raise ::Shell::AutoComplete::ParseError.new("not a valid \{{ivar.name}}")
              end
              pos_index += 1
            \{% if pann[:required] %}
            else
              raise ::Shell::AutoComplete::ParseError.new("missing positional argument: \{{ivar.name}}")
            \{% end %}
            end
          \{% end %}
        \{% end %}
        raise ::Shell::AutoComplete::ParseError.new("too many positional arguments") if pos_index < positional_tokens.size
        inst
      end

      def self.help : String
        flags = [] of ::Shell::AutoComplete::Help::FlagRow
        \{% for ivar in @type.instance_vars %}
          \{% if fann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
            \{% unless fann[:hidden] %}
              \{% alias_list = fann[:aliases] %}
              flags << {
                canonical:   \{{fann[:canonical]}}.as(String),
                aliases:     \{% if alias_list.empty? %}([] of String)\{% else %}\{{alias_list}}.map(&.as(String))\{% end %},
                short:       \{{fann[:short]}}.as(String?),
                description: \{{fann[:description]}}.as(String),
              }
            \{% end %}
          \{% end %}
        \{% end %}
        {% cmd_ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        ::Shell::AutoComplete::Help.render(
          command_name: command_name,
          description:  {{ cmd_ann && cmd_ann[:description] ? cmd_ann[:description] : "" }}.as(String),
          flags:        flags,
          header:       {{ cmd_ann && cmd_ann[:header] ? cmd_ann[:header] : nil }}.as(String?),
          footer:       {{ cmd_ann && cmd_ann[:footer] ? cmd_ann[:footer] : nil }}.as(String?),
          usage:        {{ cmd_ann && cmd_ann[:usage] ? cmd_ann[:usage] : nil }}.as(String?),
        )
      end

      def self.dispatch(argv : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : self?
        if argv.includes?("--help") || argv.includes?("-h")
          stdout.puts help
          return nil
        end
        inst = parse(argv)
        inst.run
        inst
      end
    end

    def run
      raise NotRunnable.new("#{self.class} must override #run")
    end
  end
end
