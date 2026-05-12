module Shell::AutoComplete
  abstract class Command
    record FlagInfo,
      canonical : String,
      aliases : Array(String),
      short : String?,
      description : String

    macro inherited
      SUBCOMMANDS = [] of {String, ::Shell::AutoComplete::Command.class}

      macro subcommand(klass)
        SUBCOMMANDS << { \{{klass}}.command_name, \{{klass}}.as(::Shell::AutoComplete::Command.class) }

        private def __has_subcommands_sentinel__ : Nil
        end
      end  # end macro subcommand

      def self.command_name : String
        {% ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        {% if ann && ann[:name] %}
          {{ ann[:name] }}
        {% else %}
          File.basename(PROGRAM_NAME)
        {% end %}
      end

      def self.command_description : String
        {% ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        {% if ann && ann[:description] %}
          {{ ann[:description] }}
        {% else %}
          ""
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
              \{% if fann[:shortcut_flags] %}
                \{% inner_type_sc = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                \{% for case_const in inner_type_sc.resolve.constants %}
                  \{% kebab_name = case_const.stringify.underscore.tr("_", "-") %}
                  specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
                    canonical: \{{fann[:canonical]}},
                    names: ["--" + \{{kebab_name}}],
                    takes_value: false,
                    bool_value: nil,
                    forced_value: \{{kebab_name}},
                  )
                \{% end %}
              \{% end %}
            \{% end %}
          \{% end %}
        \{% end %}
        result = ::Shell::AutoComplete::Parser.parse_argv(argv, specs)
        inst = new
        \{% for ivar in @type.instance_vars %}
          \{% if fann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
            \{% if ivar.type.id.stringify == "Bool" %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                if last_v = vs.last?
                  inst.\{{ivar.name}} = (last_v == "true")
                end
              end
            \{% elsif ivar.type.stringify.starts_with?("Array(") %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                \{% elem_type = ivar.type.type_vars[0] %}
                accum_arr = [] of \{{elem_type}}
                vs.each do |raw_v|
                  next unless raw_v
                  \{% if fann[:delimiter].is_a?(NilLiteral) %}
                    parts_for_arr = [raw_v]
                  \{% else %}
                    parts_for_arr = raw_v.split(\{{fann[:delimiter]}})
                  \{% end %}
                  parts_for_arr.each do |part|
                    accum_arr << \{{elem_type}}.__arg_transform(part, **\{{fann[:forwarded_opts]}})
                  end
                end
                inst.\{{ivar.name}} = accum_arr
              end
            \{% elsif ivar.type.stringify.starts_with?("Set(") %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                \{% elem_type = ivar.type.type_vars[0] %}
                accum_set = Set(\{{elem_type}}).new
                vs.each do |raw_v|
                  next unless raw_v
                  \{% if fann[:delimiter].is_a?(NilLiteral) %}
                    parts_for_set = [raw_v]
                  \{% else %}
                    parts_for_set = raw_v.split(\{{fann[:delimiter]}})
                  \{% end %}
                  parts_for_set.each do |part|
                    \{% if fann[:set_operations] %}
                      if part.starts_with?("-")
                        accum_set.delete(\{{elem_type}}.__arg_transform(part[1..], **\{{fann[:forwarded_opts]}}).as(\{{elem_type}}))
                      elsif part.starts_with?("+")
                        accum_set.add(\{{elem_type}}.__arg_transform(part[1..], **\{{fann[:forwarded_opts]}}).as(\{{elem_type}}))
                      else
                        accum_set.add(\{{elem_type}}.__arg_transform(part, **\{{fann[:forwarded_opts]}}).as(\{{elem_type}}))
                      end
                    \{% else %}
                      accum_set.add(\{{elem_type}}.__arg_transform(part, **\{{fann[:forwarded_opts]}}).as(\{{elem_type}}))
                    \{% end %}
                  end
                end
                inst.\{{ivar.name}} = accum_set
              end
            \{% elsif ivar.type.stringify.starts_with?("Hash(") %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                \{% val_type = ivar.type.type_vars[1] %}
                accum_hash = {} of String => \{{val_type}}
                vs.each do |raw_v|
                  next unless raw_v
                  if raw_v.starts_with?("-")
                    if key_match = raw_v.match(/\A-([A-Za-z0-9_][A-Za-z0-9_\-]*)\z/)
                      accum_hash.delete(key_match[1])
                    else
                      raise ::Shell::AutoComplete::ParseError.new("invalid hash entry: #{raw_v}")
                    end
                  elsif kv_match = raw_v.match(/\A([A-Za-z0-9_][A-Za-z0-9_\-]*)=(.*)\z/m)
                    accum_hash[kv_match[1]] = \{{val_type}}.__arg_transform(kv_match[2], **\{{fann[:forwarded_opts]}})
                  else
                    raise ::Shell::AutoComplete::ParseError.new("invalid hash entry: #{raw_v}")
                  end
                end
                inst.\{{ivar.name}} = accum_hash
              end
            \{% else %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                if raw_last = vs.last?
                  if v = raw_last
                    \{% if tw = fann[:transform_with] %}
                      transformed_value = self.\{{tw.id}}(v)
                    \{% elsif fann[:transformer_type] %}
                      transformed_value = \{{fann[:transformer_type]}}.__arg_transform(v, **\{{fann[:forwarded_opts]}})
                    \{% else %}
                      \{% inner_type = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                      transformed_value = \{{inner_type}}.__arg_transform(v, **\{{fann[:forwarded_opts]}})
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
                end
              end
            \{% end %}
          \{% end %}
        \{% end %}
        positional_tokens = result[:positional]
        positional_stack = positional_tokens.dup
        \{% begin %}
          \{%
            variadic_count = 0
            @type.instance_vars.each do |ivar|
              variadic_count += 1 if ivar.annotation(::Shell::AutoComplete::PositionalsDef)
            end
            raise "command #{@type} declares more than one positionals" if variadic_count > 1

            leading_ivars = [] of MetaVar
            trailing_ivars = [] of MetaVar
            variadic_ivar = nil
            variadic_ann = nil
            @type.instance_vars.each do |ivar|
              if ivar.annotation(::Shell::AutoComplete::PositionalDef)
                if variadic_ivar
                  trailing_ivars << ivar
                else
                  leading_ivars << ivar
                end
              elsif vann = ivar.annotation(::Shell::AutoComplete::PositionalsDef)
                variadic_ivar = ivar
                variadic_ann = vann
              end
            end

            required_leading_count = 0
            leading_ivars.each do |iv|
              required_leading_count += 1 if iv.annotation(::Shell::AutoComplete::PositionalDef)[:required]
            end
            required_trailing_count = 0
            trailing_ivars.each do |iv|
              required_trailing_count += 1 if iv.annotation(::Shell::AutoComplete::PositionalDef)[:required]
            end
            var_min = variadic_ann ? variadic_ann[:min] : 0
            min_required = required_leading_count + required_trailing_count + var_min
          %}
          if positional_stack.size < \{{ min_required }}
            raise ::Shell::AutoComplete::ParseError.new("missing required positional arguments: expected at least \{{ min_required }}, got #{positional_stack.size}")
          end
          # Shift leading scalars
          \{% for ivar in leading_ivars %}
            if positional_stack.empty?
              \{% if ivar.annotation(::Shell::AutoComplete::PositionalDef)[:required] %}
                raise ::Shell::AutoComplete::ParseError.new("missing positional argument: \{{ivar.name}}")
              \{% end %}
            else
              raw_pos_\{{ivar.name}} = positional_stack.shift
              \{% pann = ivar.annotation(::Shell::AutoComplete::PositionalDef) %}
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
            end
          \{% end %}
          # Shift variadic
          \{% if variadic_ivar %}
            \{% var_inner_type = variadic_ivar.type.type_vars[0] %}
            variadic_collected_\{{variadic_ivar.name}} = [] of \{{var_inner_type}}
            while positional_stack.size > \{{trailing_ivars.size}}
              raw_var_tok = positional_stack.shift
              variadic_collected_\{{variadic_ivar.name}} << \{{var_inner_type}}.__arg_transform(raw_var_tok)
            end
            \{% var_actual_min = variadic_ann[:min] %}
            if variadic_collected_\{{variadic_ivar.name}}.size < \{{var_actual_min}}
              raise ::Shell::AutoComplete::ParseError.new(
                "expected at least \{{var_actual_min}} value(s) for \{{variadic_ivar.name}}, got #{variadic_collected_\{{variadic_ivar.name}}.size}"
              )
            end
            inst.\{{variadic_ivar.name}} = variadic_collected_\{{variadic_ivar.name}}
          \{% end %}
          # Shift trailing scalars
          \{% for ivar in trailing_ivars %}
            if positional_stack.empty?
              \{% if ivar.annotation(::Shell::AutoComplete::PositionalDef)[:required] %}
                raise ::Shell::AutoComplete::ParseError.new("missing positional argument: \{{ivar.name}}")
              \{% end %}
            else
              raw_pos_\{{ivar.name}} = positional_stack.shift
              \{% pann = ivar.annotation(::Shell::AutoComplete::PositionalDef) %}
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
            end
          \{% end %}
          raise ::Shell::AutoComplete::ParseError.new("too many positional arguments") unless positional_stack.empty?
        \{% end %}
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
        subcommands = SUBCOMMANDS.map { |(name, klass)| {name: name, description: klass.command_description} }
        {% cmd_ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        ::Shell::AutoComplete::Help.render(
          command_name: command_name,
          description:  {{ cmd_ann && cmd_ann[:description] ? cmd_ann[:description] : "" }}.as(String),
          flags:        flags,
          subcommands:  subcommands,
          header:       {{ cmd_ann && cmd_ann[:header] ? cmd_ann[:header] : nil }}.as(String?),
          footer:       {{ cmd_ann && cmd_ann[:footer] ? cmd_ann[:footer] : nil }}.as(String?),
          usage:        {{ cmd_ann && cmd_ann[:usage] ? cmd_ann[:usage] : nil }}.as(String?),
        )
      end

      def self.shell_completion_flag_name : String
        "--shell-completion"
      end

      def self.completion_script(shell : Symbol) : String
        case shell
        when :bash
          ::Shell::AutoComplete::Completion::Bash.render(self)
        when :zsh
          ::Shell::AutoComplete::Completion::Zsh.render(self)
        when :fish
          ::Shell::AutoComplete::Completion::Fish.render(self)
        else
          raise ArgumentError.new("unsupported shell: #{shell}")
        end
      end

      def self.completion_candidates(words : Array(String), cword : Int32, current : String, prev : String) : Array(String)
        result = [] of String

        # Subcommand position: cword == 1 and subcommands exist.
        \{% if @type.has_constant?("SUBCOMMANDS") %}
          if cword == 1
            SUBCOMMANDS.each do |(sub_name, _)|
              result << sub_name if sub_name.starts_with?(current)
            end
            return result unless result.empty?
          end
        \{% end %}

        # Check if prev word is a flag that takes a value — emit value candidates.
        # @[Flags] enum trailing-comma completion.
        \{% for ivar in @type.instance_vars %}
          \{% if fann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
            \{% inner_type = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
            \{% if inner_type.resolve.annotation(::Flags) %}
              all_names_\{{ivar.name}} = [\{{fann[:canonical]}}] of String
              \{% for alias_name in fann[:aliases] %}
                all_names_\{{ivar.name}} << \{{alias_name}}
              \{% end %}
              \{% if fann[:short] %}
                all_names_\{{ivar.name}} << \{{fann[:short]}}
              \{% end %}
              if all_names_\{{ivar.name}}.includes?(prev)
                if current.includes?(",") || current.ends_with?(",")
                  existing_parts = current.chomp(",").split(",").reject(&.empty?)
                  base_prefix = current.chomp(",")
                  \{% for case_const in inner_type.resolve.constants %}
                    \{% case_name = case_const.stringify.underscore.tr("_", "-") %}
                    unless existing_parts.includes?(\{{case_name}})
                      result << base_prefix + "," + \{{case_name}}
                    end
                  \{% end %}
                end
                return result
              end
            \{% end %}
          \{% end %}
        \{% end %}

        # Flag-name completion when current starts with "-" or is empty.
        if current.starts_with?("-") || current.empty?
          \{% for ivar in @type.instance_vars %}
            \{% if fann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
              \{% inner_type_flag = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
              canonical_\{{ivar.name}} = \{{fann[:canonical]}}
              canonical_matches_\{{ivar.name}} = canonical_\{{ivar.name}}.starts_with?(current)
              if canonical_matches_\{{ivar.name}}
                result << canonical_\{{ivar.name}}
              end
              \{% if fann[:short] %}
                if \{{fann[:short]}}.starts_with?(current)
                  result << \{{fann[:short]}}
                end
              \{% end %}
              \{% if inner_type_flag.id.stringify == "Bool" && fann[:negatable] %}
                neg_name_\{{ivar.name}} = "--no-" + \{{fann[:canonical]}}.gsub(/^--/, "")
                if neg_name_\{{ivar.name}}.starts_with?(current)
                  result << neg_name_\{{ivar.name}}
                end
              \{% end %}
              # Aliases — only emit when canonical does NOT match the prefix.
              unless canonical_matches_\{{ivar.name}}
                \{% for alias_name in fann[:aliases] %}
                  if \{{alias_name}}.starts_with?(current)
                    result << \{{alias_name}}
                  end
                \{% end %}
              end
            \{% end %}
          \{% end %}
        end

        result
      end

      def self.dispatch(argv : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : ::Shell::AutoComplete::Command?
        if ::Shell::AutoComplete::Completion::Dispatcher.handle(self, argv, stdout)
          return nil
        end
        if ::Shell::AutoComplete::Completion::InstallFlag.handle(self, argv, stdout, stderr)
          return nil
        end
        if argv.includes?("--help") || argv.includes?("-h")
          stdout.puts help
          return nil
        end
        # Subcommand routing
        unless SUBCOMMANDS.empty?
          first = argv.first?
          if first.nil?
            raise ::Shell::AutoComplete::ParseError.new("expected a subcommand")
          end
          match = SUBCOMMANDS.find { |(name, _)| name == first }
          if match
            return match[1].dispatch(argv[1..], stdout: stdout, stderr: stderr)
          end
          raise ::Shell::AutoComplete::ParseError.new("unknown subcommand: #{first}")
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
