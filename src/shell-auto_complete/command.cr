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
        inst
      end

      def self.dispatch(argv : Array(String)) : self
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
