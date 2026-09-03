module Shell::AutoComplete
  abstract class Command
    record FlagInfo,
      canonical : String,
      aliases : Array(String),
      short : String?,
      description : String

    macro inherited
      SUBCOMMANDS = [] of {String, ::Shell::AutoComplete::Command.class}

      # Compile-time flag-name registry (issue #10). The `flag` macro appends
      # every spelling a declaration produces (canonical, aliases, short form,
      # generated negations, enum shortcut switches) plus the owning property
      # name, and raises on collision. `override: true` tombstones the prior
      # owner's entries and records its property in OVERRIDDEN_FLAG_IVARS,
      # which every generator consults to skip the replaced declaration.
      # When the command inherits another command (`parent:` on the command
      # macro), the registries seed from the parent's completed registries —
      # interpolation re-parses the parent's array literal into fresh nodes,
      # so later macro-time mutation of the child's copy never touches the
      # parent. Inherited-vs-own collisions and `override: true` of an
      # inherited flag then fall out of the issue #10 logic unchanged.
      FLAG_REGISTRY_NAMES   = {% if @type.superclass && @type.superclass.has_constant?("FLAG_REGISTRY_NAMES") %}{{ @type.superclass.constant("FLAG_REGISTRY_NAMES") }}{% else %}[] of ::String{% end %}
      FLAG_REGISTRY_OWNERS  = {% if @type.superclass && @type.superclass.has_constant?("FLAG_REGISTRY_OWNERS") %}{{ @type.superclass.constant("FLAG_REGISTRY_OWNERS") }}{% else %}[] of ::String{% end %}
      OVERRIDDEN_FLAG_IVARS = {% if @type.superclass && @type.superclass.has_constant?("OVERRIDDEN_FLAG_IVARS") %}{{ @type.superclass.constant("OVERRIDDEN_FLAG_IVARS") }}{% else %}[] of ::String{% end %}

      # Macro-time-readable list of this command's direct subcommand classes,
      # parallel to SUBCOMMANDS (which is built at runtime and so can't be
      # enumerated during macro expansion). The `subcommand` macro pushes each
      # class node here; `dispatch` reads it to learn subcommand flag arities
      # for routing past a subcommand-only flag (issue #22 follow-up).
      SUBCOMMAND_CLASS_NODES = [] of ::Shell::AutoComplete::Command.class

      macro subcommand(klass)
        SUBCOMMANDS << { \{{klass}}.command_name, \{{klass}}.as(::Shell::AutoComplete::Command.class) }
        \{% @type.constant("SUBCOMMAND_CLASS_NODES") << klass %}

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

      # Alternate names this command answers to when routed as a subcommand,
      # declared with `aliases:` on the `command` macro (e.g. `aliases:
      # ["mv", "rename"]` on a `move` command). Each alias routes to this
      # command exactly as its canonical name does, is offered in completion,
      # and is listed beside the name in the parent's help. The canonical name
      # is not repeated here.
      def self.command_aliases : Array(String)
        {% ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        {% if ann && ann[:aliases] %}
          {{ ann[:aliases] }}.map(&.to_s)
        {% else %}
          [] of ::String
        {% end %}
      end

      # The program name shown by --version and the version subcommand;
      # set with the `tool_name` macro (a TOOL_NAME constant, inherited
      # through parent:), defaulting to the command's name — itself
      # defaulting to the basename of PROGRAM_NAME.
      def self.version_name : String
        \{% if ([@type] + @type.ancestors).any? { |owner_type| owner_type.has_constant?("TOOL_NAME") } %}
          TOOL_NAME
        \{% else %}
          command_name
        \{% end %}
      end

      # The version string shown by --version and the version subcommand.
      # Resolution order: the `tool_version` macro's TOOL_VERSION constant
      # (inherited through parent:); then the nearest VERSION constant
      # visible from this class (the class itself, each enclosing namespace,
      # the top level, or an inherited command) — emitted as a plain
      # constant reference so Crystal's own lexical lookup picks the nearest
      # one; finally the project's `shards version`, captured at compile
      # time.
      def self.version_string : String
        \{% begin %}
          \{% if ([@type] + @type.ancestors).any? { |owner_type| owner_type.has_constant?("TOOL_VERSION") } %}
            TOOL_VERSION
          \{% else %}
            \{% version_const_found = @type.has_constant?("VERSION") || @top_level.has_constant?("VERSION") || @type.ancestors.any? { |owner_type| owner_type.has_constant?("VERSION") } %}
            \{% unless version_const_found %}
              \{% name_parts = @type.name.stringify.split("::") %}
              \{% current_namespace = @top_level %}
              \{% for name_part, part_index in name_parts %}
                \{% if part_index < name_parts.size - 1 && current_namespace && current_namespace.has_constant?(name_part) %}
                  \{% current_namespace = current_namespace.constant(name_part) %}
                  \{% if current_namespace.is_a?(TypeNode) && current_namespace.has_constant?("VERSION") %}
                    \{% version_const_found = true %}
                  \{% end %}
                \{% end %}
              \{% end %}
            \{% end %}
            \{% if version_const_found %}
              VERSION.to_s
            \{% else %}
              \{{ `shards version 2>/dev/null || echo unknown`.strip.stringify }}
            \{% end %}
          \{% end %}
        \{% end %}
      end

      # Builds this command's fully qualified path. With no `parent_prefix`
      # the command is the root, so its bare `command_name` is the whole path;
      # otherwise the parent's path is prepended (e.g. `"hf scrape"`).
      def self.qualified_name(parent_prefix : String? = nil) : String
        parent_prefix ? "#{parent_prefix} #{command_name}" : command_name
      end

      def self.command_description : String
        {% ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        {% if ann && ann[:description] %}
          {{ ann[:description] }}
        {% else %}
          ""
        {% end %}
      end

      # Resolves a token to a subcommand class by its canonical name or any
      # of its declared `aliases:`. A canonical-name match on any subcommand
      # wins over an alias match, so an alias can never shadow another
      # command's real name.
      def self.subcommand_named(name : String) : ::Shell::AutoComplete::Command.class | Nil
        SUBCOMMANDS.each do |(sub_name, sub_klass)|
          return sub_klass if sub_name == name
        end
        SUBCOMMANDS.each do |(_, sub_klass)|
          return sub_klass if sub_klass.command_aliases.includes?(name)
        end
        nil
      end

      # Directories searched for external subcommands (`external_subcommands`).
      # With `search_path:` set, the configured entries are resolved once —
      # relative ones against the running binary's directory — so the lookup is
      # independent of `PATH`. Otherwise the `PATH` directories are used, git
      # style. Returns an empty list when the feature is off.
      def self.external_subcommand_dirs : Array(String)
        \{% if @type.has_constant?("EXTERNAL_SUBCOMMANDS_SEARCH_PATH") %}
          base = File.dirname(::Process.executable_path || PROGRAM_NAME)
          EXTERNAL_SUBCOMMANDS_SEARCH_PATH.split(':').reject(&.empty?).map do |entry|
            File.expand_path(entry, base)
          end
        \{% elsif @type.has_constant?("EXTERNAL_SUBCOMMANDS") %}
          (ENV["PATH"]? || "").split(::Process::PATH_DELIMITER).reject(&.empty?)
        \{% else %}
          [] of ::String
        \{% end %}
      end

      # Resolves an external subcommand word to an executable path, or nil. A
      # word with a path separator is never looked up. With `search_path:` the
      # configured dirs are scanned in order; otherwise `PATH` is used.
      def self.external_subcommand_path(word : String) : String?
        return nil if word.empty? || word.includes?('/')
        target = command_name + "-" + word
        \{% if @type.has_constant?("EXTERNAL_SUBCOMMANDS_SEARCH_PATH") %}
          external_subcommand_dirs.each do |dir|
            candidate = File.join(dir, target)
            return candidate if File.file?(candidate) && File::Info.executable?(candidate)
          end
          nil
        \{% else %}
          ::Process.find_executable(target)
        \{% end %}
      end

      # External subcommand names (the `<word>` in `<command_name>-<word>`)
      # discovered on the search path, prefix-filtered, deduplicated, in
      # search-path order. Used to offer external subcommands in completion.
      def self.external_subcommand_names(prefix : String) : Array(String)
        names = [] of ::String
        \{% if @type.has_constant?("EXTERNAL_SUBCOMMANDS") %}
          seen = ::Set(::String).new
          exec_prefix = command_name + "-"
          external_subcommand_dirs.each do |dir|
            next unless Dir.exists?(dir)
            begin
              Dir.each_child(dir) do |entry|
                next unless entry.starts_with?(exec_prefix)
                name = entry[exec_prefix.size..]
                next if name.empty? || name.includes?('/') || seen.includes?(name)
                next unless name.starts_with?(prefix)
                full = File.join(dir, entry)
                next unless File.file?(full) && File::Info.executable?(full)
                seen << name
                names << name
              end
            rescue ::File::Error
              # Unreadable dir on the search path: skip it.
            end
          end
        \{% end %}
        names
      end

      # Invokes every `before_run` hook in the class hierarchy, parent-first,
      # on this instance. Called by `dispatch` between parse and `run`.
      def run_before_hooks : Nil
        \{% begin %}
          # Build the ownership order base-first: ancestors come nearest-first,
          # so prepending each to a list seeded with the leaf yields
          # furthest-ancestor → ... → leaf (the macro language has no reverse).
          \{% ordered_owners = [@type] %}
          \{% for ancestor in @type.ancestors %}
            \{% ordered_owners = [ancestor] + ordered_owners %}
          \{% end %}
          \{% for owner in ordered_owners %}
            \{% for meth in owner.methods %}
              \{% if meth.annotation(::Shell::AutoComplete::BeforeRunDef) %}
                self.\{{ meth.name }}
              \{% end %}
            \{% end %}
          \{% end %}
        \{% end %}
      end

      def self.flag_info(ivar_name : String) : ::Shell::AutoComplete::Command::FlagInfo
        \{% for ivar in @type.instance_vars %}
          \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
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

      # Whether the named flag (by declaration name) was explicitly given on
      # the command line, under any of its spellings: canonical, aliases,
      # short form, generated `--no-` negations, and enum shortcut switches.
      # Distinguishes an explicit value (even one equal to the default, or an
      # explicit `--no-x`) from the flag being left untouched.
      def flag_given?(name : Symbol | String) : Bool
        name_str = name.to_s
        \{% for ivar in @type.instance_vars %}
          \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
            if name_str == \{{ivar.name.stringify}}
              spellings_\{{ivar.name}} = [\{{fann[:canonical]}}] of ::String
              \{% for alias_name in fann[:aliases] %}
                spellings_\{{ivar.name}} << \{{alias_name}}
              \{% end %}
              \{% if fann[:short] %}
                spellings_\{{ivar.name}} << \{{fann[:short]}}
              \{% end %}
              \{% is_switch = ivar.type.id.stringify == "Bool" || (ivar.type.union? && ivar.type.union_types.all? { |ut| ut == Nil || ut.id.stringify == "Bool" } && ivar.type.union_types.any? { |ut| ut.id.stringify == "Bool" }) %}
              \{% if is_switch && fann[:negatable] %}
                spellings_\{{ivar.name}} << "--no-" + \{{fann[:canonical]}}.gsub(/^--/, "")
                \{% for alias_name in fann[:aliases] %}
                  spellings_\{{ivar.name}} << "--no-" + \{{alias_name}}.gsub(/^--/, "")
                \{% end %}
              \{% end %}
              \{% for sc in fann[:shortcut_switches] %}
                \{% for sc_spelling in sc[:spellings] %}
                  spellings_\{{ivar.name}} << \{{sc_spelling}}
                \{% end %}
              \{% end %}
              # A bare number is recorded as typed (`-20`), which is not one of
              # the fixed spellings, so it has to be recognized by shape here
              # too or the flag would look untouched after `-20`.
              \{% if bn = fann[:bare_number] %}
                bare_pattern_\{{ivar.name}} = \{% if bn[:pattern] %}\{{bn[:pattern]}}\{% else %}::Shell::AutoComplete::Parser.bare_number_pattern(\{{bn[:sign]}}, \{{bn[:keep_sign]}}, \{{bn[:suffix]}})\{% end %}
                return parsed_occurrences.any? { |occurrence| spellings_\{{ivar.name}}.includes?(occurrence[0]) || bare_pattern_\{{ivar.name}}.matches?(occurrence[0]) }
              \{% else %}
                return parsed_occurrences.any? { |occurrence| spellings_\{{ivar.name}}.includes?(occurrence[0]) }
              \{% end %}
            end
          \{% end %}
        \{% end %}
        raise ::ArgumentError.new("no flag named " + name_str)
      end

      def self.parse(argv : Array(String)) : self
        # A `+`-signed bare-number flag and a SetDelta variadic positional
        # both claim `+20`, and there is no reading of the command line that
        # satisfies both. Positionals and flags are declared independently, so
        # the clash can only be seen once the whole class body has expanded —
        # here.
        \{% begin %}
          \{% set_delta_ivar = @type.instance_vars.find { |iv| (pann = iv.annotation(::Shell::AutoComplete::PositionalsDef)) && pann[:set_delta] } %}
          \{% if set_delta_ivar %}
            \{% for ivar in @type.instance_vars %}
              \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && (bn = fann[:bare_number]) && (bn[:pattern] || bn[:sign] != "minus") %}
                \{% raise "flag #{ivar.name} takes a `+`-signed bare number, but the positional #{set_delta_ivar.name} is a SetDelta that reads `+name` tokens, so `+20` is ambiguous; give the flag `bare_number: {sign: :minus}` or drop set_operations from the positional" %}
              \{% end %}
            \{% end %}
          \{% end %}
        \{% end %}

        # Delimited flags (issue: delimited_flag) capture a run of raw tokens
        # ending at a delimiter, which is discarded; parsing then resumes on
        # the remaining tokens. Extract those runs before the normal parser
        # runs, so flag-looking tokens inside a captured run are taken
        # literally and never reach the flag parser. The captured values are
        # held here and assigned once the instance exists.
        \{% begin %}
          \{% delimited_ivars = @type.instance_vars.select { |iv| iv.annotation(::Shell::AutoComplete::DelimitedFlagDef) } %}
          \{% unless delimited_ivars.empty? %}
            \{% for iv in delimited_ivars %}
              delimited_captured_\{{iv.name}} = nil
            \{% end %}
            delimited_cleaned = [] of ::String
            delimited_i = 0
            while delimited_i < argv.size
              delimited_tok = argv[delimited_i]
              delimited_matched = false
              \{% for iv in delimited_ivars %}
                \{% dann = iv.annotation(::Shell::AutoComplete::DelimitedFlagDef) %}
                \{% dann_inner = iv.type.union? ? iv.type.union_types.reject { |t| t == Nil }[0] : iv.type %}
                \{% dann_inner_q = (dann_inner.stringify.starts_with?("::") || dann_inner.stringify.starts_with?("(")) ? dann_inner : "::#{dann_inner}".id %}
                if !delimited_matched && (\{% for sp, sp_i in dann[:names] %}\{% if sp_i > 0 %} || \{% end %}delimited_tok == \{{sp}}\{% end %})
                  delimited_matched = true
                  delimited_value_\{{iv.name}} = \{{dann_inner_q}}.new
                  delimited_i += 1
                  while delimited_i < argv.size && argv[delimited_i] != \{{dann[:delimiter]}}
                    delimited_value_\{{iv.name}} << argv[delimited_i]
                    delimited_i += 1
                  end
                  delimited_i += 1 if delimited_i < argv.size
                  delimited_captured_\{{iv.name}} = delimited_value_\{{iv.name}}
                end
              \{% end %}
              unless delimited_matched
                delimited_cleaned << delimited_tok
                delimited_i += 1
              end
            end
            argv = delimited_cleaned
          \{% end %}
        \{% end %}

        specs = [] of ::Shell::AutoComplete::Parser::FlagSpec
        \{% for ivar in @type.instance_vars %}
          \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
            \{% is_switch = ivar.type.id.stringify == "Bool" || (ivar.type.union? && ivar.type.union_types.all? { |ut| ut == Nil || ut.id.stringify == "Bool" } && ivar.type.union_types.any? { |ut| ut.id.stringify == "Bool" }) %}
            \{% if is_switch %}
              pos_names_\{{ivar.name}} = [\{{fann[:canonical]}}] of ::String
              \{% for alias_name in fann[:aliases] %}
                pos_names_\{{ivar.name}} << \{{alias_name}}
              \{% end %}
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
                neg_names_\{{ivar.name}} = ["--no-" + \{{fann[:canonical]}}.gsub(/^--/, "")] of ::String
                \{% for alias_name in fann[:aliases] %}
                  neg_names_\{{ivar.name}} << "--no-" + \{{alias_name}}.gsub(/^--/, "")
                \{% end %}
                specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
                  canonical: \{{fann[:canonical]}},
                  names: neg_names_\{{ivar.name}},
                  takes_value: false,
                  bool_value: false,
                )
              \{% end %}
            \{% else %}
              names_\{{ivar.name}} = [\{{fann[:canonical]}}] of ::String
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
              # Shortcut switches — the per-case switches and the configured
              # aliases alike — are forced-value specs feeding the same flag's
              # value stream, so last-value-wins ordering resolves them
              # against each other with no extra machinery. Every spelling the
              # switch answers to (its long form and any short) shares one
              # spec, so they are interchangeable on the command line.
              \{% for sc in fann[:shortcut_switches] %}
                specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
                  canonical: \{{fann[:canonical]}},
                  names: \{{sc[:spellings]}},
                  takes_value: false,
                  bool_value: nil,
                  forced_value: \{{sc[:value]}},
                )
              \{% end %}
              # A bare-number spelling (`-20`, `+50`) is matched by shape
              # rather than by name, and feeds this flag's own value stream,
              # so it transforms, validates and resolves last-wins exactly as
              # the long form does.
              \{% if bn = fann[:bare_number] %}
                specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
                  canonical: \{{fann[:canonical]}},
                  names: [] of ::String,
                  takes_value: false,
                  bool_value: nil,
                  pattern: \{% if bn[:pattern] %}\{{bn[:pattern]}}\{% else %}::Shell::AutoComplete::Parser.bare_number_pattern(\{{bn[:sign]}}, \{{bn[:keep_sign]}}, \{{bn[:suffix]}})\{% end %},
                )
              \{% end %}
            \{% end %}
          \{% end %}
        \{% end %}
        \{% for meth in ([@type] + @type.ancestors).map(&.methods).reduce([] of Def) { |acc, meths| acc + meths } %}
          \{% if gann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) %}
            \{% for spelling in gann[:spellings] %}
              specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
                canonical: \{{spelling}},
                names: [\{{spelling}}] of ::String,
                takes_value: true,
                bool_value: nil,
              )
            \{% end %}
          \{% end %}
        \{% end %}
        result = ::Shell::AutoComplete::Parser.parse_argv(argv, specs, dash_positionals: \{{ @type.instance_vars.any? { |iv| iv.annotation(::Shell::AutoComplete::PositionalsDef) && iv.annotation(::Shell::AutoComplete::PositionalsDef)[:set_delta] } }})
        inst = new
        inst.parsed_occurrences = result[:occurrences]
        \{% for iv in @type.instance_vars %}
          \{% if iv.annotation(::Shell::AutoComplete::DelimitedFlagDef) %}
            if delimited_final_\{{iv.name}} = delimited_captured_\{{iv.name}}
              inst.\{{iv.name}} = delimited_final_\{{iv.name}}
            end
          \{% end %}
        \{% end %}
        \{% if ([@type] + @type.ancestors).any? { |owner_type| owner_type.methods.any? { |m| m.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) } } %}
          # Ordered flag groups: deliver each member occurrence, in
          # command-line order, to the group's handler. The block records into
          # properties; an ArgumentError from it becomes a clean ParseError
          # carrying the matched spelling.
          result[:occurrences].each do |occurrence|
            case occurrence[0]
            \{% for meth in ([@type] + @type.ancestors).map(&.methods).reduce([] of Def) { |acc, meths| acc + meths } %}
              \{% if gann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) %}
                \{% for spelling in gann[:spellings] %}
                  when \{{spelling}}
                    begin
                      inst.\{{meth.name}}(\{{spelling.id.stringify.gsub(/\A--/, "")}}, occurrence[1] || "")
                    rescue group_error : ::ArgumentError
                      raise ::Shell::AutoComplete::ParseError.new(\{{spelling}} + ": " + (group_error.message || "invalid value"))
                    end
                \{% end %}
              \{% end %}
            \{% end %}
            end
          end
        \{% end %}
        \{% for ivar in @type.instance_vars %}
          \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
            \{% is_switch = ivar.type.id.stringify == "Bool" || (ivar.type.union? && ivar.type.union_types.all? { |ut| ut == Nil || ut.id.stringify == "Bool" } && ivar.type.union_types.any? { |ut| ut.id.stringify == "Bool" }) %}
            \{% if is_switch %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                if last_v = vs.last?
                  inst.\{{ivar.name}} = (last_v == "true")
                end
              end
            \{% elsif ivar.type.stringify.starts_with?("Array(") %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                \{% elem_type = ivar.type.type_vars[0] %}
                \{% elem_type_q = (elem_type.stringify.starts_with?("::") || elem_type.stringify.starts_with?("(")) ? elem_type : "::#{elem_type}".id %}
                \{% per_flag_transform_method = "__arg_transform_" + ivar.name.stringify %}
                \{% has_per_flag_transform = @type.class.methods.any? { |m| m.name.stringify == per_flag_transform_method } %}
                \{% per_flag_validate_method = "__arg_validate_" + ivar.name.stringify %}
                \{% has_per_flag_validate = @type.class.methods.any? { |m| m.name.stringify == per_flag_validate_method } %}
                \{% elem_tw = fann[:transform_with] %}
                \{% elem_vw = fann[:validate_with] %}
                accum_arr = [] of \{{elem_type_q}}
                vs.each do |raw_v|
                  next unless raw_v
                  \{% if fann[:delimiter].is_a?(NilLiteral) %}
                    parts_for_arr = [raw_v]
                  \{% else %}
                    parts_for_arr = raw_v.split(\{{fann[:delimiter]}})
                  \{% end %}
                  parts_for_arr.each do |part|
                    begin
                      \{% if has_per_flag_transform %}
                        elem_value = self.\{{per_flag_transform_method.id}}(part)
                      \{% elsif elem_tw %}
                        elem_value = self.\{{elem_tw.id}}(part)
                      \{% else %}
                        elem_value = \{{elem_type_q}}.__arg_transform(part, **\{{fann[:forwarded_opts]}})
                      \{% end %}
                    rescue elem_error : ::ArgumentError
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": " + (elem_error.message || "invalid value"))
                    end
                    \{% if has_per_flag_validate %}
                      elem_check = self.\{{per_flag_validate_method.id}}(elem_value)
                    \{% elsif elem_vw %}
                      elem_check = self.\{{elem_vw.id}}(elem_value)
                    \{% elsif elem_type.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                      elem_check = \{{elem_type_q}}.__arg_validate(elem_value, **\{{fann[:forwarded_opts]}})
                    \{% else %}
                      elem_check = true
                    \{% end %}
                    case elem_check
                    when true
                      # ok
                    when ::String
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": " + elem_check.as(::String))
                    when false
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": not a valid \{{ivar.name}}")
                    end
                    accum_arr << elem_value
                  end
                end
                inst.\{{ivar.name}} = accum_arr
              end
            \{% elsif ivar.type.stringify.starts_with?("Set(") %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                \{% elem_type = ivar.type.type_vars[0] %}
                \{% elem_type_q = (elem_type.stringify.starts_with?("::") || elem_type.stringify.starts_with?("(")) ? elem_type : "::#{elem_type}".id %}
                \{% per_flag_transform_method = "__arg_transform_" + ivar.name.stringify %}
                \{% has_per_flag_transform = @type.class.methods.any? { |m| m.name.stringify == per_flag_transform_method } %}
                \{% per_flag_validate_method = "__arg_validate_" + ivar.name.stringify %}
                \{% has_per_flag_validate = @type.class.methods.any? { |m| m.name.stringify == per_flag_validate_method } %}
                \{% elem_tw = fann[:transform_with] %}
                \{% elem_vw = fann[:validate_with] %}
                accum_set = ::Set(\{{elem_type_q}}).new
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
                        set_op_delete = true
                        set_payload = part[1..]
                      elsif part.starts_with?("+")
                        set_op_delete = false
                        set_payload = part[1..]
                      else
                        set_op_delete = false
                        set_payload = part
                      end
                    \{% else %}
                      set_op_delete = false
                      set_payload = part
                    \{% end %}
                    begin
                      \{% if has_per_flag_transform %}
                        elem_value = self.\{{per_flag_transform_method.id}}(set_payload)
                      \{% elsif elem_tw %}
                        elem_value = self.\{{elem_tw.id}}(set_payload)
                      \{% else %}
                        elem_value = \{{elem_type_q}}.__arg_transform(set_payload, **\{{fann[:forwarded_opts]}})
                      \{% end %}
                    rescue elem_error : ::ArgumentError
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": " + (elem_error.message || "invalid value"))
                    end
                    if set_op_delete
                      accum_set.delete(elem_value.as(\{{elem_type_q}}))
                    else
                      \{% if has_per_flag_validate %}
                        elem_check = self.\{{per_flag_validate_method.id}}(elem_value)
                      \{% elsif elem_vw %}
                        elem_check = self.\{{elem_vw.id}}(elem_value)
                      \{% elsif elem_type.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                        elem_check = \{{elem_type_q}}.__arg_validate(elem_value, **\{{fann[:forwarded_opts]}})
                      \{% else %}
                        elem_check = true
                      \{% end %}
                      case elem_check
                      when true
                        # ok
                      when ::String
                        raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": " + elem_check.as(::String))
                      when false
                        raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": not a valid \{{ivar.name}}")
                      end
                      accum_set.add(elem_value.as(\{{elem_type_q}}))
                    end
                  end
                end
                inst.\{{ivar.name}} = accum_set
              end
            \{% elsif ivar.type.stringify.starts_with?("Hash(") %}
              if vs = result[:values][\{{fann[:canonical]}}]?
                \{% val_type = ivar.type.type_vars[1] %}
                \{% val_type_q = (val_type.stringify.starts_with?("::") || val_type.stringify.starts_with?("(")) ? val_type : "::#{val_type}".id %}
                \{% per_flag_transform_method = "__arg_transform_" + ivar.name.stringify %}
                \{% has_per_flag_transform = @type.class.methods.any? { |m| m.name.stringify == per_flag_transform_method } %}
                \{% per_flag_validate_method = "__arg_validate_" + ivar.name.stringify %}
                \{% has_per_flag_validate = @type.class.methods.any? { |m| m.name.stringify == per_flag_validate_method } %}
                \{% elem_tw = fann[:transform_with] %}
                \{% elem_vw = fann[:validate_with] %}
                accum_hash = {} of ::String => \{{val_type_q}}
                vs.each do |raw_v|
                  next unless raw_v
                  if raw_v.starts_with?("-")
                    if key_match = raw_v.match(::Shell::AutoComplete::HashFlag::DELETE_RE)
                      \{% if fann[:hash_operations] %}
                        accum_hash.delete(key_match[1])
                      \{% else %}
                        raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": deletion is disabled for this flag (hash_operations: false); use #{key_match[1]}=VALUE to assign")
                      \{% end %}
                    elsif raw_v.matches?(::Shell::AutoComplete::HashFlag::DELETE_ASSIGN_RE)
                      raise ::Shell::AutoComplete::ParseError.new("invalid hash entry: #{raw_v} (use #{raw_v[1..]} to assign, or #{raw_v.partition('=')[0]} to delete)")
                    else
                      raise ::Shell::AutoComplete::ParseError.new("invalid hash entry: #{raw_v}")
                    end
                  elsif kv_match = raw_v.match(::Shell::AutoComplete::HashFlag::KEY_VALUE_RE)
                    begin
                      \{% if has_per_flag_transform %}
                        elem_value = self.\{{per_flag_transform_method.id}}(kv_match[2])
                      \{% elsif elem_tw %}
                        elem_value = self.\{{elem_tw.id}}(kv_match[2])
                      \{% else %}
                        elem_value = \{{val_type_q}}.__arg_transform(kv_match[2], **\{{fann[:forwarded_opts]}})
                      \{% end %}
                    rescue elem_error : ::ArgumentError
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": " + (elem_error.message || "invalid value"))
                    end
                    \{% if has_per_flag_validate %}
                      elem_check = self.\{{per_flag_validate_method.id}}(elem_value)
                    \{% elsif elem_vw %}
                      elem_check = self.\{{elem_vw.id}}(elem_value)
                    \{% elsif val_type.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                      elem_check = \{{val_type_q}}.__arg_validate(elem_value, **\{{fann[:forwarded_opts]}})
                    \{% else %}
                      elem_check = true
                    \{% end %}
                    case elem_check
                    when true
                      # ok
                    when ::String
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": " + elem_check.as(::String))
                    when false
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": not a valid \{{ivar.name}}")
                    end
                    accum_hash[kv_match[1]] = elem_value
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
                    \{% is_nullable = ivar.type.union? && ivar.type.union_types.includes?(Nil) %}
                    \{% inner_type = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                    \{% inner_type_q = ((inner_type.stringify.starts_with?("::") || inner_type.stringify.starts_with?("(")) ? inner_type : "::#{inner_type}".id) %}
                    \{% inner_is_string = inner_type.id.stringify == "String" %}
                    # Nillability via empty string: an explicit empty value on a
                    # nullable non-String type resets the property to nil.
                    \{% if is_nullable && !inner_is_string %}
                      if v.empty?
                        inst.\{{ivar.name}} = nil
                      else
                    \{% end %}
                    \{% per_flag_transform_method = "__arg_transform_" + ivar.name.stringify %}
                    \{% has_per_flag_transform = @type.class.methods.any? { |m| m.name.stringify == per_flag_transform_method } %}
                    begin
                      \{% if has_per_flag_transform %}
                        transformed_value = self.\{{per_flag_transform_method.id}}(v)
                      \{% elsif tw = fann[:transform_with] %}
                        transformed_value = self.\{{tw.id}}(v)
                      \{% elsif fann[:transformer_type] %}
                        transformed_value = \{{fann[:transformer_type]}}.__arg_transform(v, **\{{fann[:forwarded_opts]}})
                      \{% else %}
                        transformed_value = \{{inner_type_q}}.__arg_transform(v, **\{{fann[:forwarded_opts]}})
                      \{% end %}
                    rescue scalar_error : ::ArgumentError
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": " + (scalar_error.message || "invalid value"))
                    end
                    inst.\{{ivar.name}} = transformed_value
                    # `ivar.type` is the *storage* type, which for a remapped
                    # flag (`Types::PositiveInt` stored as `Int32`) is not the
                    # type carrying `__arg_validate`. Prefer the declared type
                    # recorded in `transformer_type`, exactly as the transform
                    # dispatch above and the positional path do — otherwise a
                    # synthetic type's validator is silently skipped.
                    \{% inner_type_v = fann[:transformer_type] || inner_type %}
                    \{% inner_type_v_q = fann[:transformer_type] || inner_type_q %}
                    \{% per_flag_validate_method = "__arg_validate_" + ivar.name.stringify %}
                    \{% has_per_flag_validate = @type.class.methods.any? { |m| m.name.stringify == per_flag_validate_method } %}
                    \{% if has_per_flag_validate %}
                      result_v = self.\{{per_flag_validate_method.id}}(transformed_value)
                    \{% elsif vw = fann[:validate_with] %}
                      result_v = self.\{{vw.id}}(transformed_value)
                    \{% elsif inner_type_v.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                      result_v = \{{inner_type_v_q}}.__arg_validate(transformed_value, **\{{fann[:forwarded_opts]}})
                    \{% else %}
                      result_v = true
                    \{% end %}
                    case result_v
                    when true
                      # ok
                    when String
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": " + result_v.as(String))
                    when false
                      raise ::Shell::AutoComplete::ParseError.new(\{{fann[:canonical]}} + ": not a valid \{{ivar.name}}")
                    end
                    \{% if is_nullable && !inner_is_string %}
                      end
                    \{% end %}
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
              \{% elsif tt = pann[:transformer_type] %}
                transformed_pos_\{{ivar.name}} = \{{tt}}.__arg_transform(raw_pos_\{{ivar.name}})
              \{% else %}
                \{% pos_inner_type = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                \{% pos_inner_type_q = ((pos_inner_type.stringify.starts_with?("::") || pos_inner_type.stringify.starts_with?("(")) ? pos_inner_type : "::#{pos_inner_type}".id) %}
                transformed_pos_\{{ivar.name}} = \{{pos_inner_type_q}}.__arg_transform(raw_pos_\{{ivar.name}})
              \{% end %}
              inst.\{{ivar.name}} = transformed_pos_\{{ivar.name}}
              \{% if vw = pann[:validate_with] %}
                result_v_pos_\{{ivar.name}} = self.\{{vw.id}}(transformed_pos_\{{ivar.name}})
              \{% else %}
                \{% pos_inner_type_v_res = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                \{% pos_inner_type_v = pann[:transformer_type] || pos_inner_type_v_res %}
                \{% pos_inner_type_v_q = pann[:transformer_type] || ((pos_inner_type_v_res.stringify.starts_with?("::") || pos_inner_type_v_res.stringify.starts_with?("(")) ? pos_inner_type_v_res : "::#{pos_inner_type_v_res}".id) %}
                \{% if pos_inner_type_v.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                  result_v_pos_\{{ivar.name}} = \{{pos_inner_type_v_q}}.__arg_validate(transformed_pos_\{{ivar.name}}, **\{{pann[:forwarded_opts]}})
                \{% else %}
                  result_v_pos_\{{ivar.name}} = true
                \{% end %}
              \{% end %}
              case result_v_pos_\{{ivar.name}}
              when true
                # ok
              when String
                raise ::Shell::AutoComplete::ParseError.new(\{{ivar.name.stringify}} + ": " + result_v_pos_\{{ivar.name}}.as(String))
              when false
                raise ::Shell::AutoComplete::ParseError.new("not a valid \{{ivar.name}}")
              end
            end
          \{% end %}
          # Shift variadic
          \{% if variadic_ivar %}
            \{% if variadic_ann[:set_delta] %}
              # SetDelta: merge each `+name`/`-name`/`name` token's single-entry
              # delta into one Hash(String, Bool); last write wins on a repeat.
              variadic_collected_\{{variadic_ivar.name}} = ::Hash(::String, ::Bool).new
              while positional_stack.size > \{{trailing_ivars.size}}
                raw_var_tok = positional_stack.shift
                variadic_collected_\{{variadic_ivar.name}}.merge!(::Shell::AutoComplete::Types::SetDelta.__arg_transform(raw_var_tok))
              end
            \{% else %}
              \{% var_storage_type = variadic_ivar.type.type_vars[0] %}
              \{% var_storage_type_q = ((var_storage_type.stringify.starts_with?("::") || var_storage_type.stringify.starts_with?("(")) ? var_storage_type : "::#{var_storage_type}".id) %}
              \{% var_transform_type_q = variadic_ann[:transformer_type] || var_storage_type_q %}
              variadic_collected_\{{variadic_ivar.name}} = [] of \{{var_storage_type_q}}
              while positional_stack.size > \{{trailing_ivars.size}}
                raw_var_tok = positional_stack.shift
                # `transform_with:`/`validate_with:` apply per element here, the
                # same way they do on a scalar positional. The macro accepts
                # both options on a variadic declaration, so skipping them made
                # a declared transform a silent no-op.
                begin
                  \{% if var_tw = variadic_ann[:transform_with] %}
                    var_elem_\{{variadic_ivar.name}} = self.\{{var_tw.id}}(raw_var_tok)
                  \{% else %}
                    var_elem_\{{variadic_ivar.name}} = \{{var_transform_type_q}}.__arg_transform(raw_var_tok)
                  \{% end %}
                rescue var_error : ::ArgumentError
                  raise ::Shell::AutoComplete::ParseError.new(
                    \{{variadic_ivar.name.stringify}} + ": " + (var_error.message || "invalid value")
                  )
                end
                \{% if var_vw = variadic_ann[:validate_with] %}
                  var_check_\{{variadic_ivar.name}} = self.\{{var_vw.id}}(var_elem_\{{variadic_ivar.name}})
                \{% else %}
                  \{% var_validate_type = variadic_ann[:transformer_type] || var_storage_type %}
                  \{% var_validate_type_q = variadic_ann[:transformer_type] || var_storage_type_q %}
                  \{% if var_validate_type.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                    var_check_\{{variadic_ivar.name}} = \{{var_validate_type_q}}.__arg_validate(var_elem_\{{variadic_ivar.name}}, **\{{variadic_ann[:forwarded_opts]}})
                  \{% else %}
                    var_check_\{{variadic_ivar.name}} = true
                  \{% end %}
                \{% end %}
                case var_check_\{{variadic_ivar.name}}
                when true
                  # ok
                when String
                  raise ::Shell::AutoComplete::ParseError.new(
                    \{{variadic_ivar.name.stringify}} + ": " + var_check_\{{variadic_ivar.name}}.as(String)
                  )
                when false
                  raise ::Shell::AutoComplete::ParseError.new("not a valid \{{variadic_ivar.name}}")
                end
                variadic_collected_\{{variadic_ivar.name}} << var_elem_\{{variadic_ivar.name}}
              end
            \{% end %}
            \{% var_actual_min = variadic_ann[:min] %}
            if variadic_collected_\{{variadic_ivar.name}}.size < \{{var_actual_min}}
              raise ::Shell::AutoComplete::ParseError.new(
                "expected at least \{{var_actual_min}} value(s) for \{{variadic_ivar.name}}, got #{variadic_collected_\{{variadic_ivar.name}}.size}"
              )
            end
            \{% var_actual_max = variadic_ann[:max] %}
            if variadic_collected_\{{variadic_ivar.name}}.size > \{{var_actual_max}}
              raise ::Shell::AutoComplete::ParseError.new(
                "too many <\{{variadic_ivar.name}}> args: got #{variadic_collected_\{{variadic_ivar.name}}.size}, max \{{var_actual_max}}"
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
              \{% elsif tt = pann[:transformer_type] %}
                transformed_pos_\{{ivar.name}} = \{{tt}}.__arg_transform(raw_pos_\{{ivar.name}})
              \{% else %}
                \{% pos_inner_type = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                \{% pos_inner_type_q = ((pos_inner_type.stringify.starts_with?("::") || pos_inner_type.stringify.starts_with?("(")) ? pos_inner_type : "::#{pos_inner_type}".id) %}
                transformed_pos_\{{ivar.name}} = \{{pos_inner_type_q}}.__arg_transform(raw_pos_\{{ivar.name}})
              \{% end %}
              inst.\{{ivar.name}} = transformed_pos_\{{ivar.name}}
              \{% if vw = pann[:validate_with] %}
                result_v_pos_\{{ivar.name}} = self.\{{vw.id}}(transformed_pos_\{{ivar.name}})
              \{% else %}
                \{% pos_inner_type_v_res = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                \{% pos_inner_type_v = pann[:transformer_type] || pos_inner_type_v_res %}
                \{% pos_inner_type_v_q = pann[:transformer_type] || ((pos_inner_type_v_res.stringify.starts_with?("::") || pos_inner_type_v_res.stringify.starts_with?("(")) ? pos_inner_type_v_res : "::#{pos_inner_type_v_res}".id) %}
                \{% if pos_inner_type_v.resolve.class.methods.any? { |m| m.name.stringify == "__arg_validate" } %}
                  result_v_pos_\{{ivar.name}} = \{{pos_inner_type_v_q}}.__arg_validate(transformed_pos_\{{ivar.name}}, **\{{pann[:forwarded_opts]}})
                \{% else %}
                  result_v_pos_\{{ivar.name}} = true
                \{% end %}
              \{% end %}
              case result_v_pos_\{{ivar.name}}
              when true
                # ok
              when String
                raise ::Shell::AutoComplete::ParseError.new(\{{ivar.name.stringify}} + ": " + result_v_pos_\{{ivar.name}}.as(String))
              when false
                raise ::Shell::AutoComplete::ParseError.new("not a valid \{{ivar.name}}")
              end
            end
          \{% end %}
          raise ::Shell::AutoComplete::ParseError.new("too many positional arguments") unless positional_stack.empty?
        \{% end %}
        inst
      end

      def self.help(parent_prefix : String? = nil) : String
        flags = [] of ::Shell::AutoComplete::Help::FlagRow
        \{% for ivar in @type.instance_vars %}
          \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
            \{% unless fann[:hidden] %}
              \{% alias_list = fann[:aliases] %}
              \{% inherited_ivar = @type.superclass && @type.superclass.instance_vars.any? { |sup_ivar| sup_ivar.name == ivar.name } %}
              flags << {
                canonical:   \{{fann[:canonical]}}.as(::String),
                aliases:     \{% if alias_list.empty? %}([] of ::String)\{% else %}\{{alias_list}}.map(&.as(::String))\{% end %},
                short:       \{{fann[:short]}}.as(::String?),
                description: \{{fann[:description]}}.as(::String),
                placeholder: \{{fann[:placeholder]}}.as(::String?),
                group:       \{% if fann[:group] %}\{{fann[:group]}}.as(::String?)\{% elsif inherited_ivar %}"Inherited options".as(::String?)\{% else %}nil.as(::String?)\{% end %},
                indent:      false,
              }
              # A bare-number spelling has no name to list among the flag's
              # forms, so it gets its own indented row showing the shape it
              # accepts. Nothing else in help would reveal that `-20` works.
              \{% if bn = fann[:bare_number] %}
                flags << {
                  canonical:   \{{bn[:label]}}.as(::String),
                  aliases:     ([] of ::String),
                  short:       nil.as(::String?),
                  description: \{% if bn[:description] %}\{{bn[:description]}}\{% else %}("Same as " + \{{fann[:canonical]}} + " with that number")\{% end %}.as(::String),
                  placeholder: nil.as(::String?),
                  group:       \{% if fann[:group] %}\{{fann[:group]}}.as(::String?)\{% elsif inherited_ivar %}"Inherited options".as(::String?)\{% else %}nil.as(::String?)\{% end %},
                  indent:      true,
                }
              \{% end %}
              # Shortcut switches render indented under the flag they force a
              # value on. A switch derived from an enum case is listed only
              # when it carries a short spelling, which nothing else in help
              # would reveal — a plain `--debug` is already implied by the
              # flag's own `debug|info|warn` placeholder.
              \{% for sc in fann[:shortcut_switches] %}
                \{% if sc[:help] %}
                  flags << {
                    canonical:   \{{sc[:spellings][0]}}.as(::String),
                    aliases:     \{% if sc[:spellings].size <= 1 %}([] of ::String)\{% else %}\{{sc[:spellings][1..-1]}}.map(&.as(::String))\{% end %},
                    short:       nil.as(::String?),
                    description: \{% if sc[:description] %}\{{sc[:description]}}\{% else %}("Same as " + \{{fann[:canonical]}} + " " + \{{sc[:value]}})\{% end %}.as(::String),
                    placeholder: nil.as(::String?),
                    group:       \{% if fann[:group] %}\{{fann[:group]}}.as(::String?)\{% elsif inherited_ivar %}"Inherited options".as(::String?)\{% else %}nil.as(::String?)\{% end %},
                    indent:      true,
                  }
                \{% end %}
              \{% end %}
            \{% end %}
          \{% end %}
        \{% end %}
        \{% for ivar in @type.instance_vars %}
          \{% if dann = ivar.annotation(::Shell::AutoComplete::DelimitedFlagDef) %}
            \{% dnames = dann[:names] %}
            flags << {
              canonical:   \{{dnames[0]}}.as(::String),
              aliases:     \{% if dnames.size <= 1 %}([] of ::String)\{% else %}\{{dnames[1..-1]}}.map(&.as(::String))\{% end %},
              short:       nil.as(::String?),
              description: \{{dann[:description]}}.as(::String),
              placeholder: ("<args>... " + \{{dann[:delimiter]}}).as(::String?),
              group:       nil.as(::String?),
              indent:      false,
            }
          \{% end %}
        \{% end %}
        \{% for meth in ([@type] + @type.ancestors).map(&.methods).reduce([] of Def) { |acc, meths| acc + meths } %}
          \{% if gann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) %}
            \{% for member_idx in 0...gann[:spellings].size %}
              flags << {
                canonical:   \{{gann[:spellings][member_idx]}}.as(::String),
                aliases:     ([] of ::String),
                short:       nil.as(::String?),
                description: \{{gann[:descriptions][member_idx]}}.as(::String),
                placeholder: nil.as(::String?),
                group:       \{{gann[:description]}}.as(::String?),
                indent:      false,
              }
            \{% end %}
          \{% end %}
        \{% end %}
        subcommands = SUBCOMMANDS.map { |(name, klass)| {name: name, aliases: klass.command_aliases, description: klass.command_description} }
        positionals = [] of ::Shell::AutoComplete::Help::PositionalRow
        \{% for ivar in @type.instance_vars %}
          \{% if pann = ivar.annotation(::Shell::AutoComplete::PositionalDef) %}
            \{% unless pann[:hidden] %}
              positionals << {
                name:        \{{ivar.name.stringify}}.as(::String),
                description: \{{pann[:description]}}.as(::String),
                variadic:    false,
              }
            \{% end %}
          \{% elsif vann = ivar.annotation(::Shell::AutoComplete::PositionalsDef) %}
            \{% unless vann[:hidden] %}
              positionals << {
                name:        \{{ivar.name.stringify}}.as(::String),
                description: \{{vann[:description]}}.as(::String),
                variadic:    true,
              }
            \{% end %}
          \{% end %}
        \{% end %}
        {% cmd_ann = @type.annotation(::Shell::AutoComplete::CommandDef) %}
        ::Shell::AutoComplete::Help.render(
          command_name:   command_name,
          section_order:  {{ cmd_ann && cmd_ann[:help_sections] ? cmd_ann[:help_sections] : nil }}.as(::Array(::Symbol)?),
          description:    {{ cmd_ann && cmd_ann[:description] ? cmd_ann[:description] : "" }}.as(::String),
          flags:          flags,
          subcommands:    subcommands,
          positionals:    positionals,
          header:         {{ cmd_ann && cmd_ann[:header] ? cmd_ann[:header] : nil }}.as(::String?),
          footer:         {{ cmd_ann && cmd_ann[:footer] ? cmd_ann[:footer] : nil }}.as(::String?),
          usage:          {{ cmd_ann && cmd_ann[:usage] ? cmd_ann[:usage] : nil }}.as(::String?),
          qualified_name: qualified_name(parent_prefix),
        )
      end

      def self.all_help(parent_prefix : String? = nil) : String
        qualified = qualified_name(parent_prefix)
        String.build do |io|
          io << "==== " << qualified << " ====\n"
          rendered = help(parent_prefix)
          io << rendered
          io << '\n' unless rendered.ends_with?('\n')
          SUBCOMMANDS.each do |sub|
            sub_klass = sub[1]
            io << '\n' << sub_klass.all_help(qualified)
          end
        end
      end

      def self.shell_completion_flag_name : String
        "--shell-completion"
      end

      # Generates the shell completion script. *executable*, when given, is the
      # command the generated callback invokes for `__complete` — pass an
      # absolute path so completion runs a specific binary regardless of `PATH`
      # (useful for a dev build); the command name still registers the
      # completion. Defaults to the command name.
      def self.completion_script(shell : Symbol, executable : String? = nil) : String
        case shell
        when :bash
          ::Shell::AutoComplete::Completion::Bash.render(self, executable)
        when :zsh
          ::Shell::AutoComplete::Completion::Zsh.render(self, executable)
        when :fish
          ::Shell::AutoComplete::Completion::Fish.render(self, executable)
        else
          raise ArgumentError.new("unsupported shell: #{shell}")
        end
      end

      def self.completion_candidates(words : Array(String), cword : Int32, current : String, prev : String) : Array(String)
        result = [] of ::String

        # Delimited-flag capture (issue: delimited_flag): if the cursor sits
        # inside an un-terminated capture run — after a delimited spelling and
        # before its delimiter — the tokens are an opaque run. For a plain
        # delimited flag, offer nothing rather than this command's own flag
        # names. For `external_command: true`, emit a COMMAND directive
        # carrying the captured words so the shell completes them as a command
        # line (command names for the first word, the command's own completion
        # after).
        \{% begin %}
          \{% delimited_ivars_c = @type.instance_vars.select { |iv| iv.annotation(::Shell::AutoComplete::DelimitedFlagDef) } %}
          \{% unless delimited_ivars_c.empty? %}
            delimited_active_term = nil.as(::String?)
            delimited_capture_external = false
            delimited_capture_start = 0
            delimited_scan = 1
            while delimited_scan < cword && delimited_scan < words.size
              delimited_word = words[delimited_scan]
              if term = delimited_active_term
                delimited_active_term = nil if delimited_word == term
              else
                \{% for iv in delimited_ivars_c %}
                  \{% dann = iv.annotation(::Shell::AutoComplete::DelimitedFlagDef) %}
                  if \{% for sp, sp_i in dann[:names] %}\{% if sp_i > 0 %} || \{% end %}delimited_word == \{{sp}}\{% end %}
                    delimited_active_term = \{{dann[:delimiter]}}
                    delimited_capture_external = \{{ dann[:external_command] ? true : false }}
                    delimited_capture_start = delimited_scan + 1
                  end
                \{% end %}
              end
              delimited_scan += 1
            end
            unless delimited_active_term.nil?
              if delimited_capture_external
                delimited_typed = delimited_capture_start <= cword ? words[delimited_capture_start...cword] : [] of ::String
                return [::Shell::AutoComplete::Completion::Directive.command(delimited_typed)]
              end
              return result
            end
          \{% end %}
        \{% end %}

        # Check if prev word is a flag that takes a value — emit value candidates.
        # complete_with: and per-flag __arg_complete_<name> dispatch. This runs
        # before every derived-candidate block so an explicit completer always
        # wins, including over @[Flags] trailing-comma completion.
        \{% for ivar in @type.instance_vars %}
          \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
            \{% per_flag_complete_method = "__arg_complete_" + ivar.name.stringify %}
            \{% has_per_flag_complete = @type.class.methods.any? { |m| m.name.stringify == per_flag_complete_method } %}
            \{% cw = fann[:complete_with] %}
            \{% if cw || has_per_flag_complete %}
              flag_matched_\{{ivar.name}} = false
              if prev == \{{fann[:canonical]}}
                flag_matched_\{{ivar.name}} = true
              end
              \{% for alias_name in fann[:aliases] %}
                if prev == \{{alias_name}}
                  flag_matched_\{{ivar.name}} = true
                end
              \{% end %}
              \{% if fann[:short] %}
                if prev == \{{fann[:short]}}
                  flag_matched_\{{ivar.name}} = true
                end
              \{% end %}
              if flag_matched_\{{ivar.name}}
                ctx_\{{ivar.name}} = ::Shell::AutoComplete::CompletionContext.new(
                  words: words,
                  cword: cword,
                )
                \{% if has_per_flag_complete %}
                  sub_candidates_\{{ivar.name}} = self.\{{per_flag_complete_method.id}}(ctx_\{{ivar.name}})
                \{% elsif cw %}
                  sub_candidates_\{{ivar.name}} = self.\{{cw.id}}(ctx_\{{ivar.name}})
                \{% end %}
                sub_candidates_\{{ivar.name}}.each { |candidate| result << candidate }
                return result
              end
            \{% end %}
          \{% end %}
        \{% end %}

        # @[Flags] enum value completion: after any spelling of the flag, offer
        # the kebab-cased member names (prefix-filtered, alias constants once);
        # once the value has a trailing or embedded comma, offer the remaining
        # members appended after the existing ones.
        \{% for ivar in @type.instance_vars %}
          \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
            \{% inner_type = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
            \{% if inner_type.resolve.annotation(::Flags) %}
              all_names_\{{ivar.name}} = [\{{fann[:canonical]}}] of ::String
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
                else
                  \{% fv_seen = [] of ::StringLiteral %}
                  \{% for case_const in inner_type.resolve.constants %}
                    \{% case_name = case_const.stringify.underscore.tr("_", "-") %}
                    \{% unless fv_seen.includes?(case_name) %}
                      \{% fv_seen << case_name %}
                      if \{{case_name}}.starts_with?(current)
                        result << \{{case_name}}
                      end
                    \{% end %}
                  \{% end %}
                end
                return result
              end
            \{% end %}
          \{% end %}
        \{% end %}

        # Plain (non-@[Flags]) enum value completion: after a value-taking enum
        # flag (any of its spellings), offer the enum's kebab-cased member
        # names. Flags with a `complete_with:` or per-flag completer returned
        # above, so an explicit completer always wins over these derived
        # candidates.
        \{% for ivar in @type.instance_vars %}
          \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
            \{% inner_type_ev = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
            \{% if inner_type_ev.resolve < ::Enum && !inner_type_ev.resolve.annotation(::Flags) %}
              enum_flag_names_\{{ivar.name}} = [\{{fann[:canonical]}}] of ::String
              \{% for alias_name in fann[:aliases] %}
                enum_flag_names_\{{ivar.name}} << \{{alias_name}}
              \{% end %}
              \{% if fann[:short] %}
                enum_flag_names_\{{ivar.name}} << \{{fann[:short]}}
              \{% end %}
              if enum_flag_names_\{{ivar.name}}.includes?(prev)
                \{% ev_seen = [] of ::StringLiteral %}
                \{% for case_const in inner_type_ev.resolve.constants %}
                  \{% case_name = case_const.stringify.underscore.tr("_", "-") %}
                  \{% unless ev_seen.includes?(case_name) %}
                    \{% ev_seen << case_name %}
                    if \{{case_name}}.starts_with?(current)
                      result << \{{case_name}}
                    end
                  \{% end %}
                \{% end %}
                return result
              end
            \{% end %}
          \{% end %}
        \{% end %}

        # Derived flag-value completion (issue #48): when prev is any spelling
        # of a value-taking flag, the cursor sits on that flag's value, so this
        # branch always returns — falling through would wrongly offer flag
        # names (or positional candidates) as the value. `choices:` wins over
        # type-derived candidates; otherwise the flag's declared type resolves
        # to its `__arg_complete` (Path/File/Dir emit the native-completion
        # directive, exactly as positionals do), collections complete their
        # element type, and types with no completer yield no candidates.
        # Tokens after a `--` terminator are positional, so the branch is
        # skipped there.
        dash_dash_index = 1
        dash_dash_before_cursor = false
        while dash_dash_index < cword && dash_dash_index < words.size
          if words[dash_dash_index] == "--"
            dash_dash_before_cursor = true
            break
          end
          dash_dash_index += 1
        end
        unless dash_dash_before_cursor
          if prev == shell_completion_flag_name
            ::Shell::AutoComplete::Completion::InstallFlag::SHELLS.each do |shell_name|
              result << shell_name if shell_name.starts_with?(current)
            end
            return result
          end
          \{% for ivar in @type.instance_vars %}
            \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
              \{% is_switch_dv = ivar.type.id.stringify == "Bool" || (ivar.type.union? && ivar.type.union_types.all? { |ut| ut == Nil || ut.id.stringify == "Bool" } && ivar.type.union_types.any? { |ut| ut.id.stringify == "Bool" }) %}
              \{% unless is_switch_dv %}
                dv_names_\{{ivar.name}} = [\{{fann[:canonical]}}] of ::String
                \{% for alias_name in fann[:aliases] %}
                  dv_names_\{{ivar.name}} << \{{alias_name}}
                \{% end %}
                \{% if fann[:short] %}
                  dv_names_\{{ivar.name}} << \{{fann[:short]}}
                \{% end %}
                if dv_names_\{{ivar.name}}.includes?(prev)
                  \{% dv_fwd = fann[:forwarded_opts] %}
                  \{% dv_choices = dv_fwd.is_a?(NamedTupleLiteral) ? dv_fwd[:choices] : nil %}
                  # `choices:` may be written as a constant reference rather
                  # than an array literal. Validation resolves it at runtime,
                  # so without resolving it here too the flag would validate
                  # against the list while completing nothing.
                  \{% if dv_choices.is_a?(Path) %}
                    \{% dv_choices_res = dv_choices.resolve? %}
                    \{% dv_choices = dv_choices_res if dv_choices_res.is_a?(ArrayLiteral) %}
                  \{% end %}
                  \{% if dv_choices.is_a?(ArrayLiteral) %}
                    \{% dv_c_inner = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                    \{% dv_c_base = dv_c_inner.id.stringify.gsub(/\A::/, "").split("(")[0] %}
                    \{% dv_c_delim = fann[:delimiter] %}
                    \{% if ["Array", "Set"].includes?(dv_c_base) && dv_c_delim.is_a?(StringLiteral) %}
                      # A split-on-delimiter collection completes the element
                      # after the last delimiter, keeping the earlier elements
                      # as the candidate's prefix — same shape as the
                      # type-derived branch below.
                      if dv_c_idx_\{{ivar.name}} = current.rindex(\{{dv_c_delim}})
                        dv_c_start_\{{ivar.name}} = dv_c_idx_\{{ivar.name}} + \{{dv_c_delim}}.size
                        dv_c_prefix_\{{ivar.name}} = current[dv_c_start_\{{ivar.name}}..]
                        dv_c_base_\{{ivar.name}} = current[0, dv_c_start_\{{ivar.name}}]
                        dv_c_seen_\{{ivar.name}} = dv_c_base_\{{ivar.name}}.split(\{{dv_c_delim}})
                        \{% for choice in dv_choices %}
                          \{% choice_str = choice.is_a?(StringLiteral) ? choice : choice.id.stringify %}
                          if \{{choice_str}}.starts_with?(dv_c_prefix_\{{ivar.name}}) && !dv_c_seen_\{{ivar.name}}.includes?(\{{choice_str}})
                            result << dv_c_base_\{{ivar.name}} + \{{choice_str}}
                          end
                        \{% end %}
                      else
                        \{% for choice in dv_choices %}
                          \{% choice_str = choice.is_a?(StringLiteral) ? choice : choice.id.stringify %}
                          if \{{choice_str}}.starts_with?(current)
                            result << \{{choice_str}}
                          end
                        \{% end %}
                      end
                    \{% else %}
                      \{% for choice in dv_choices %}
                        \{% choice_str = choice.is_a?(StringLiteral) ? choice : choice.id.stringify %}
                        if \{{choice_str}}.starts_with?(current)
                          result << \{{choice_str}}
                        end
                      \{% end %}
                    \{% end %}
                  \{% else %}
                    \{% dv_inner_res = ivar.type.union? ? ivar.type.union_types.reject { |t| t == Nil }[0] : ivar.type %}
                    \{% dv_base = dv_inner_res.id.stringify.gsub(/\A::/, "").split("(")[0] %}
                    \{% if ["Array", "Set"].includes?(dv_base) %}
                      \{% dv_el = dv_inner_res.type_vars[0] %}
                      \{% dv_el_q = ((dv_el.stringify.starts_with?("::") || dv_el.stringify.starts_with?("(")) ? dv_el : "::#{dv_el}".id) %}
                      # Enums inherit __arg_complete from the Enum base, which
                      # metaclass-method existence checks don't see.
                      \{% if dv_el.resolve < ::Enum || dv_el.resolve.class.methods.any? { |m| m.name.stringify == "__arg_complete" } %}
                        \{% dv_delim = fann[:delimiter] %}
                        \{% if dv_delim.is_a?(StringLiteral) %}
                          # Split-on-delimiter collection: complete the element
                          # after the last delimiter, keeping the earlier
                          # elements as the candidate's prefix. Directive
                          # sentinels can't be prefixed, so they are only
                          # emitted while the value has no delimiter yet.
                          if dv_delim_idx_\{{ivar.name}} = current.rindex(\{{dv_delim}})
                            dv_elem_start_\{{ivar.name}} = dv_delim_idx_\{{ivar.name}} + \{{dv_delim}}.size
                            dv_elem_prefix_\{{ivar.name}} = current[dv_elem_start_\{{ivar.name}}..]
                            dv_elem_base_\{{ivar.name}} = current[0, dv_elem_start_\{{ivar.name}}]
                            \{{dv_el_q}}.__arg_complete(dv_elem_prefix_\{{ivar.name}}).each do |candidate|
                              next if ::Shell::AutoComplete::Completion::Directive.directive?(candidate)
                              if candidate.starts_with?(dv_elem_prefix_\{{ivar.name}})
                                result << dv_elem_base_\{{ivar.name}} + candidate
                              end
                            end
                          else
                            \{{dv_el_q}}.__arg_complete(current).each { |candidate| result << candidate }
                          end
                        \{% else %}
                          \{{dv_el_q}}.__arg_complete(current).each { |candidate| result << candidate }
                        \{% end %}
                      \{% end %}
                    \{% else %}
                      \{% dv_inner = fann[:transformer_type] || dv_inner_res %}
                      \{% dv_inner_q = fann[:transformer_type] || ((dv_inner_res.stringify.starts_with?("::") || dv_inner_res.stringify.starts_with?("(")) ? dv_inner_res : "::#{dv_inner_res}".id) %}
                      \{% if dv_inner.resolve < ::Enum || dv_inner.resolve.class.methods.any? { |m| m.name.stringify == "__arg_complete" } %}
                        \{{dv_inner_q}}.__arg_complete(current).each { |candidate| result << candidate }
                      \{% end %}
                    \{% end %}
                  \{% end %}
                  return result
                end
              \{% end %}
            \{% end %}
          \{% end %}
          # Ordered-flag-group spellings take a free-form value: no derived
          # candidates, but the value position must not fall through to
          # flag-name completion.
          \{% for meth in ([@type] + @type.ancestors).map(&.methods).reduce([] of Def) { |acc, meths| acc + meths } %}
            \{% if gann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) %}
              \{% for spelling in gann[:spellings] %}
                return result if prev == \{{spelling}}
              \{% end %}
            \{% end %}
          \{% end %}
        end

        # Subcommand-name completion. This sits after the flag-value blocks so a
        # flag's value position never resolves to a subcommand name, and those
        # blocks return before reaching here whenever `prev` takes a value.
        #
        # A routing command cannot also declare positionals (that pairing is a
        # compile error), so every word before the cursor is either a flag, a
        # value a flag consumed, or the subcommand word itself — and the
        # completion dispatcher already descends past the subcommand word and
        # removes it. The cursor is therefore still at the subcommand slot
        # unless a subcommand word survives before it. Gating on `cword == 1`
        # instead meant any preceding flag silenced this entirely, so
        # `app --verbose <TAB>` offered nothing and `app --verbose sub <TAB>`
        # offered no sub-subcommands.
        \{% if @type.has_constant?("SUBCOMMANDS") %}
          unless current.starts_with?("-")
            sub_slot_taken = false
            (1...cword).each do |sub_scan_index|
              break if sub_scan_index >= words.size
              sub_token = words[sub_scan_index]
              # Past `--` every token is positional, never a subcommand word.
              if sub_token == "--"
                sub_slot_taken = true
                break
              end
              if subcommand_named(sub_token)
                sub_slot_taken = true
                break
              end
              \{% if @type.has_constant?("EXTERNAL_SUBCOMMANDS") %}
                # A resolved external subcommand word also consumes the slot;
                # its own arguments are the external command's to complete.
                if !sub_token.starts_with?("-") && external_subcommand_path(sub_token)
                  sub_slot_taken = true
                  break
                end
              \{% end %}
            end
            unless sub_slot_taken
              SUBCOMMANDS.each do |(sub_name, sub_klass)|
                result << sub_name if sub_name.starts_with?(current)
                sub_klass.command_aliases.each do |sub_alias|
                  result << sub_alias if sub_alias.starts_with?(current)
                end
              end
              \{% if @type.has_constant?("EXTERNAL_SUBCOMMANDS") %}
                external_subcommand_names(current).each do |ext_name|
                  result << ext_name unless result.includes?(ext_name)
                end
              \{% end %}
              return result unless result.empty?
            end
          end
        \{% end %}

        # Positional-argument completion. Only engaged when the cursor is not on a
        # flag (`current` not starting with "-"); the slot the cursor maps to is
        # resolved through the flags it follows, then dispatched to that
        # positional's `complete_with:` method or its type's `__arg_complete`
        # (path types emit a native-completion directive). If the slot has no
        # completer, control falls through to flag-name completion below.
        \{% begin %}
          \{%
            p_leading = [] of MetaVar
            p_variadic = nil
            @type.instance_vars.each do |pv|
              if pv.annotation(::Shell::AutoComplete::PositionalDef)
                p_leading << pv unless p_variadic
              elsif pv.annotation(::Shell::AutoComplete::PositionalsDef)
                p_variadic = pv
              end
            end
          %}
          \{% if !p_leading.empty? || p_variadic %}
            unless current.starts_with?("-")
              pos_value_flags = ::Set(::String).new
              \{% for ivar in @type.instance_vars %}
                \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
                  \{% is_switch = ivar.type.id.stringify == "Bool" || (ivar.type.union? && ivar.type.union_types.all? { |ut| ut == Nil || ut.id.stringify == "Bool" } && ivar.type.union_types.any? { |ut| ut.id.stringify == "Bool" }) %}
                  \{% unless is_switch %}
                    pos_value_flags << \{{fann[:canonical]}}
                    \{% for alias_name in fann[:aliases] %}
                      pos_value_flags << \{{alias_name}}
                    \{% end %}
                    \{% if fann[:short] %}
                      pos_value_flags << \{{fann[:short]}}
                    \{% end %}
                  \{% end %}
                \{% end %}
              \{% end %}
              \{% for meth in ([@type] + @type.ancestors).map(&.methods).reduce([] of Def) { |acc, meths| acc + meths } %}
                \{% if gann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) %}
                  \{% for spelling in gann[:spellings] %}
                    pos_value_flags << \{{spelling}}
                  \{% end %}
                \{% end %}
              \{% end %}
              pos_bare_patterns = [] of ::Regex
              \{% for ivar in @type.instance_vars %}
                \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
                  \{% if bn = fann[:bare_number] %}
                    pos_bare_patterns << \{% if bn[:pattern] %}\{{bn[:pattern]}}\{% else %}::Shell::AutoComplete::Parser.bare_number_pattern(\{{bn[:sign]}}, \{{bn[:keep_sign]}}, \{{bn[:suffix]}})\{% end %}
                  \{% end %}
                \{% end %}
              \{% end %}
              pos_slot = ::Shell::AutoComplete::Completion::Positional.index_at(words, cword, pos_value_flags, pos_bare_patterns)
              if pos_slot
                \{% for i in 0...p_leading.size %}
                  \{% pivar = p_leading[i] %}
                  \{% pann = pivar.annotation(::Shell::AutoComplete::PositionalDef) %}
                  \{% p_inner_res = pivar.type.union? ? pivar.type.union_types.reject { |t| t == Nil }[0] : pivar.type %}
                  \{% p_inner = pann[:transformer_type] || p_inner_res %}
                  \{% p_inner_q = pann[:transformer_type] || ((p_inner_res.stringify.starts_with?("::") || p_inner_res.stringify.starts_with?("(")) ? p_inner_res : "::#{p_inner_res}".id) %}
                  if pos_slot == \{{i}}
                    \{% if cw = pann[:complete_with] %}
                      pos_ctx = ::Shell::AutoComplete::CompletionContext.new(words: words, cword: cword)
                      self.\{{cw.id}}(pos_ctx).each { |candidate| result << candidate }
                      return result
                    \{% elsif p_inner.resolve < ::Enum || p_inner.resolve.class.methods.any? { |m| m.name.stringify == "__arg_complete" } %}
                      \{{p_inner_q}}.__arg_complete(current).each { |candidate| result << candidate }
                      return result
                    \{% end %}
                  end
                \{% end %}
                \{% if p_variadic %}
                  \{% vann = p_variadic.annotation(::Shell::AutoComplete::PositionalsDef) %}
                  \{% v_str = p_variadic.type.stringify %}
                  \{% if vann[:transformer_type] %}
                    \{% v_inner = vann[:transformer_type] %}
                    \{% v_inner_q = v_inner %}
                  \{% elsif v_str.starts_with?("Hash(") %}
                    \{% v_inner = p_variadic.type.type_vars[1] %}
                    \{% v_inner_q = ((v_inner.stringify.starts_with?("::") || v_inner.stringify.starts_with?("(")) ? v_inner : "::#{v_inner}".id) %}
                  \{% else %}
                    \{% v_inner = p_variadic.type.type_vars[0] %}
                    \{% v_inner_q = ((v_inner.stringify.starts_with?("::") || v_inner.stringify.starts_with?("(")) ? v_inner : "::#{v_inner}".id) %}
                  \{% end %}
                  if pos_slot >= \{{p_leading.size}}
                    \{% if cw = vann[:complete_with] %}
                      var_ctx = ::Shell::AutoComplete::CompletionContext.new(words: words, cword: cword)
                      self.\{{cw.id}}(var_ctx).each { |candidate| result << candidate }
                      return result
                    \{% elsif v_inner.resolve < ::Enum || v_inner.resolve.class.methods.any? { |m| m.name.stringify == "__arg_complete" } %}
                      \{{v_inner_q}}.__arg_complete(current).each { |candidate| result << candidate }
                      return result
                    \{% end %}
                  end
                \{% end %}
              end
            end
          \{% end %}
        \{% end %}

        # Flag-name completion when current starts with "-" or is empty.
        if current.starts_with?("-") || current.empty?
          \{% for ivar in @type.instance_vars %}
            \{% if dann = ivar.annotation(::Shell::AutoComplete::DelimitedFlagDef) %}
              \{% for sp in dann[:names] %}
                if \{{sp}}.starts_with?(current)
                  result << \{{sp}}
                end
              \{% end %}
            \{% end %}
          \{% end %}
          \{% for meth in ([@type] + @type.ancestors).map(&.methods).reduce([] of Def) { |acc, meths| acc + meths } %}
            \{% if gann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) %}
              \{% for spelling in gann[:spellings] %}
                if \{{spelling}}.starts_with?(current)
                  result << \{{spelling}}
                end
              \{% end %}
            \{% end %}
          \{% end %}
          \{% for ivar in @type.instance_vars %}
            \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
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
              \{% for sc in fann[:shortcut_switches] %}
                \{% for sc_spelling in sc[:spellings] %}
                  if \{{sc_spelling}}.starts_with?(current)
                    result << \{{sc_spelling}}
                  end
                \{% end %}
              \{% end %}
              # Aliases — only emit when canonical does NOT match the prefix.
              unless canonical_matches_\{{ivar.name}}
                \{% for alias_name in fann[:aliases] %}
                  if \{{alias_name}}.starts_with?(current)
                    result << \{{alias_name}}
                  end
                  \{% if inner_type_flag.id.stringify == "Bool" && fann[:negatable] %}
                    neg_alias_\{{ivar.name}} = "--no-" + \{{alias_name}}.gsub(/^--/, "")
                    if neg_alias_\{{ivar.name}}.starts_with?(current)
                      result << neg_alias_\{{ivar.name}}
                    end
                  \{% end %}
                \{% end %}
              end
            \{% end %}
          \{% end %}
        end

        result
      end

      def self.dispatch(argv : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR, rescue_errors : Bool = true, parent_prefix : String? = nil) : ::Shell::AutoComplete::Command?
        if rescue_errors
          begin
            return dispatch(argv, stdout: stdout, stderr: stderr, rescue_errors: false, parent_prefix: parent_prefix)
          rescue ex : ::Shell::AutoComplete::ParseError
            stderr.puts "#{ex.command_path || command_name}: #{ex.message}"
            Process.exit(1)
          end
        end

        qualified = qualified_name(parent_prefix)

        begin
          if ::Shell::AutoComplete::Completion::Dispatcher.handle(self, argv, stdout)
            return
          end
          if ::Shell::AutoComplete::Completion::InstallFlag.handle(self, argv, stdout, stderr)
            return
          end
          # Routing (issue #22): walk argv past this command's own flags (and
          # the values they consume) to find the subcommand word, so shared
          # flags may appear before or after it, and a routing command
          # invoked with only its own flags parses them instead of raising
          # "unknown subcommand". Tokens after -- never route. `external_
          # subcommands` enables the walk even with no declared subcommands,
          # so a pure PATH-dispatch tool still routes.
          routing_active = !SUBCOMMANDS.empty?
          \{% if @type.has_constant?("EXTERNAL_SUBCOMMANDS") %}
            routing_active = true
          \{% end %}
          if routing_active
            if argv.empty?
              stdout.puts help(parent_prefix)
              return
            end
            value_flag_tokens = ::Set(::String).new
            switch_flag_tokens = ::Set(::String){"--help", "-h", "--all-help"}
            value_flag_tokens << shell_completion_flag_name
            \{% if !([@type] + @type.ancestors).any? { |owner_type| owner_type.has_constant?("VERSION_FLAG_DISABLED") } && !@type.constant("FLAG_REGISTRY_NAMES").includes?("--version") %}
              switch_flag_tokens << "--version"
            \{% end %}
            \{% for ivar in @type.instance_vars %}
              \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
                \{% is_switch = ivar.type.id.stringify == "Bool" || (ivar.type.union? && ivar.type.union_types.all? { |ut| ut == Nil || ut.id.stringify == "Bool" } && ivar.type.union_types.any? { |ut| ut.id.stringify == "Bool" }) %}
                \{% if is_switch %}
                  switch_flag_tokens << \{{fann[:canonical]}}
                  \{% for alias_name in fann[:aliases] %}
                    switch_flag_tokens << \{{alias_name}}
                  \{% end %}
                  \{% if fann[:short] %}
                    switch_flag_tokens << \{{fann[:short]}}
                  \{% end %}
                  \{% if fann[:negatable] %}
                    switch_flag_tokens << "--no-" + \{{fann[:canonical]}}.gsub(/^--/, "")
                    \{% for alias_name in fann[:aliases] %}
                      switch_flag_tokens << "--no-" + \{{alias_name}}.gsub(/^--/, "")
                    \{% end %}
                  \{% end %}
                \{% else %}
                  value_flag_tokens << \{{fann[:canonical]}}
                  \{% for alias_name in fann[:aliases] %}
                    value_flag_tokens << \{{alias_name}}
                  \{% end %}
                  \{% if fann[:short] %}
                    value_flag_tokens << \{{fann[:short]}}
                  \{% end %}
                  \{% for sc in fann[:shortcut_switches] %}
                    \{% for sc_spelling in sc[:spellings] %}
                      switch_flag_tokens << \{{sc_spelling}}
                    \{% end %}
                  \{% end %}
                \{% end %}
              \{% end %}
            \{% end %}
            \{% for meth in ([@type] + @type.ancestors).map(&.methods).reduce([] of Def) { |acc, meths| acc + meths } %}
              \{% if gann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef) %}
                \{% for spelling in gann[:spellings] %}
                  value_flag_tokens << \{{spelling}}
                \{% end %}
              \{% end %}
            \{% end %}
            # Routing union (issue #22 follow-up): so `app --format json list`
            # routes when only `list` declares `--format`, the parent must know
            # `--format` takes a value to walk past it to the subcommand word.
            # We gather the value/switch arity of every direct subcommand's
            # flags, skipping spellings the parent already routes (parent is
            # authoritative). The chosen subcommand still accepts or rejects
            # the flag itself, so a flag typed before the wrong subcommand is
            # rejected there. Subcommands disagreeing on a spelling's arity is
            # a compile error — the parent can't know how far to skip.
            \{% begin %}
            \{%
              parent_names = ["--help", "-h", "--all-help"]
              parent_names << (@type.has_constant?("SHELL_COMPLETION_FLAG") ? @type.constant("SHELL_COMPLETION_FLAG") : "--shell-completion")
              parent_names << "--version"
              parent_flag_owners = [@type] + @type.ancestors
              parent_flag_owners.each do |owner_type|
                owner_type.instance_vars.each do |ivar|
                  if (pfann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify)
                    parent_names << pfann[:canonical]
                    pfann[:aliases].each { |alias_name| parent_names << alias_name }
                    parent_names << pfann[:short] if pfann[:short]
                    p_is_switch = ivar.type.id.stringify == "Bool" || (ivar.type.union? && ivar.type.union_types.all? { |ut| ut == Nil || ut.id.stringify == "Bool" } && ivar.type.union_types.any? { |ut| ut.id.stringify == "Bool" })
                    if p_is_switch && pfann[:negatable]
                      parent_names << "--no-" + pfann[:canonical].gsub(/^--/, "")
                      pfann[:aliases].each { |alias_name| parent_names << "--no-" + alias_name.gsub(/^--/, "") }
                    end
                    pfann[:shortcut_switches].each do |psc|
                      psc[:spellings].each { |sp| parent_names << sp }
                    end
                  end
                end
                owner_type.methods.each do |meth|
                  if pgann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef)
                    pgann[:spellings].each { |spelling| parent_names << spelling }
                  end
                end
              end

              union_value = [] of ::StringLiteral
              union_switch = [] of ::StringLiteral
              union_conflict = nil
              @type.constant("SUBCOMMAND_CLASS_NODES").each do |sub_node|
                sub_type = sub_node.resolve
                sub_type.instance_vars.each do |ivar|
                  if (sfann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !sub_type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify)
                    s_is_switch = ivar.type.id.stringify == "Bool" || (ivar.type.union? && ivar.type.union_types.all? { |ut| ut == Nil || ut.id.stringify == "Bool" } && ivar.type.union_types.any? { |ut| ut.id.stringify == "Bool" })
                    sub_value = [] of ::StringLiteral
                    sub_switch = [] of ::StringLiteral
                    if s_is_switch
                      sub_switch << sfann[:canonical]
                      sfann[:aliases].each { |alias_name| sub_switch << alias_name }
                      sub_switch << sfann[:short] if sfann[:short]
                      if sfann[:negatable]
                        sub_switch << "--no-" + sfann[:canonical].gsub(/^--/, "")
                        sfann[:aliases].each { |alias_name| sub_switch << "--no-" + alias_name.gsub(/^--/, "") }
                      end
                    else
                      sub_value << sfann[:canonical]
                      sfann[:aliases].each { |alias_name| sub_value << alias_name }
                      sub_value << sfann[:short] if sfann[:short]
                      sfann[:shortcut_switches].each do |ssc|
                        ssc[:spellings].each { |sp| sub_switch << sp }
                      end
                    end
                    sub_value.each do |sp|
                      unless parent_names.includes?(sp)
                        union_conflict = sp if union_switch.includes?(sp)
                        union_value << sp unless union_value.includes?(sp)
                      end
                    end
                    sub_switch.each do |sp|
                      unless parent_names.includes?(sp)
                        union_conflict = sp if union_value.includes?(sp)
                        union_switch << sp unless union_switch.includes?(sp)
                      end
                    end
                  end
                end
                sub_type.methods.each do |meth|
                  if sgann = meth.annotation(::Shell::AutoComplete::OrderedFlagGroupDef)
                    sgann[:spellings].each do |sp|
                      unless parent_names.includes?(sp)
                        union_conflict = sp if union_switch.includes?(sp)
                        union_value << sp unless union_value.includes?(sp)
                      end
                    end
                  end
                end
              end
              if union_conflict
                raise "subcommands of #{@type} disagree on whether #{union_conflict} takes a value, so the parent cannot route past it; give the flag the same arity on every subcommand that declares it, or declare it on the parent"
              end
            %}
            \{% for sp in union_value %}
              value_flag_tokens << \{{ sp }}
            \{% end %}
            \{% for sp in union_switch %}
              switch_flag_tokens << \{{ sp }}
            \{% end %}
            \{% end %}
            # A delimited flag (issue: delimited_flag) on this routing command
            # consumes a run of tokens up to its delimiter, so the walk skips
            # that whole run rather than reading the captured tokens (or the
            # delimiter) as a subcommand word. The capture stays in argv and is
            # handled by the chosen command's own parse (via parent: for an
            # inherited delimited flag).
            delimited_route = {} of ::String => ::String
            \{% for ivar in @type.instance_vars %}
              \{% if dann = ivar.annotation(::Shell::AutoComplete::DelimitedFlagDef) %}
                \{% for sp in dann[:names] %}
                  delimited_route[\{{sp}}] = \{{dann[:delimiter]}}
                \{% end %}
              \{% end %}
            \{% end %}
            # Bare-number spellings are matched by shape, so the walk cannot
            # look them up in the token lists. A `+50` does not even read as a
            # flag, and without this the walk would take it for the subcommand
            # word. Subcommand-declared shapes are gathered too, for the same
            # reason the routing union gathers their flag names: the parent has
            # to walk past a flag it does not declare itself.
            route_bare_patterns = [] of ::Regex
            \{% for ivar in @type.instance_vars %}
              \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
                \{% if bn = fann[:bare_number] %}
                  route_bare_patterns << \{% if bn[:pattern] %}\{{bn[:pattern]}}\{% else %}::Shell::AutoComplete::Parser.bare_number_pattern(\{{bn[:sign]}}, \{{bn[:keep_sign]}}, \{{bn[:suffix]}})\{% end %}
                \{% end %}
              \{% end %}
            \{% end %}
            \{% for sub_node in @type.constant("SUBCOMMAND_CLASS_NODES") %}
              \{% for ivar in sub_node.resolve.instance_vars %}
                \{% if (sfann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !sub_node.resolve.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) %}
                  \{% if sbn = sfann[:bare_number] %}
                    route_bare_patterns << \{% if sbn[:pattern] %}\{{sbn[:pattern]}}\{% else %}::Shell::AutoComplete::Parser.bare_number_pattern(\{{sbn[:sign]}}, \{{sbn[:keep_sign]}}, \{{sbn[:suffix]}})\{% end %}
                  \{% end %}
                \{% end %}
              \{% end %}
            \{% end %}
            route_index = 0
            subcommand_word = nil
            subcommand_index = -1
            while route_index < argv.size
              route_token = argv[route_index]
              if route_delim_term = delimited_route[route_token]?
                route_index += 1
                while route_index < argv.size && argv[route_index] != route_delim_term
                  route_index += 1
                end
                route_index += 1 if route_index < argv.size
                next
              end
              break if route_token == "--"
              if !route_bare_patterns.empty? && route_bare_patterns.any?(&.matches?(route_token))
                # Carries its own value, so nothing follows it to skip.
                route_index += 1
                next
              end
              if route_token.starts_with?("-") && route_token.size > 1
                route_name = route_token.partition('=')[0]
                if value_flag_tokens.includes?(route_name)
                  route_index += 1 unless route_token.includes?('=')
                elsif switch_flag_tokens.includes?(route_name)
                  # consumes no value
                else
                  raise ::Shell::AutoComplete::ParseError.new("unknown flag: #{route_name}")
                end
              else
                subcommand_word = route_token
                subcommand_index = route_index
                break
              end
              route_index += 1
            end
            if subcommand_word
              if match = subcommand_named(subcommand_word)
                routed_argv = argv.dup
                routed_argv.delete_at(subcommand_index)
                return match.dispatch(routed_argv, stdout: stdout, stderr: stderr, rescue_errors: false, parent_prefix: qualified)
              end
              \{% if @type.has_constant?("EXTERNAL_SUBCOMMANDS") %}
                # git-style external subcommand: no declared match, so look for
                # `<command_name>-<word>` on the search path and hand off
                # blindly. Everything after the subcommand word is passed
                # through. `exec` replaces this process, so exit status and
                # signals propagate naturally.
                if external_path = external_subcommand_path(subcommand_word)
                  ::Process.exec(external_path, argv[(subcommand_index + 1)..])
                end
              \{% end %}
              raise ::Shell::AutoComplete::ParseError.new("unknown subcommand: #{subcommand_word}")
            end
            # No subcommand word: a routing command invoked with only its own
            # flags — fall through to the intercepts and parse + run.
          end
          # Intercepts respect the -- terminator, consistent with the parser:
          # a literal "--help" after -- is a positional, not a help request.
          pre_double_dash = (double_dash_index = argv.index("--")) ? argv[0...double_dash_index] : argv
          # --all-help intercept: only fires when this command has subcommands
          if pre_double_dash.includes?("--all-help") && !SUBCOMMANDS.empty?
            stdout.puts all_help(parent_prefix)
            return
          end
          # --help / -h intercept at THIS level (no subcommand matched)
          if pre_double_dash.includes?("--help") || pre_double_dash.includes?("-h")
            stdout.puts help(parent_prefix)
            return
          end
          # --version intercept: root level only, and only while no flag has
          # claimed the spelling (a declared --version flag wins; the
          # disable_version_flag macro turns it off without claiming it).
          \{% if !([@type] + @type.ancestors).any? { |owner_type| owner_type.has_constant?("VERSION_FLAG_DISABLED") } && !@type.constant("FLAG_REGISTRY_NAMES").includes?("--version") %}
            if parent_prefix.nil? && pre_double_dash.includes?("--version")
              stdout.puts "#{version_name} #{version_string}"
              return
            end
          \{% end %}
          # Immediate flags: print-reference-data-and-exit switches fire as
          # soon as their spelling appears before --, regardless of whether
          # the rest of the line would validate — like their callback-parser
          # ancestors, which ran handlers during parse.
          \{% for ivar in @type.instance_vars %}
            \{% if (fann = ivar.annotation(::Shell::AutoComplete::FlagDef)) && !@type.constant("OVERRIDDEN_FLAG_IVARS").includes?(ivar.name.stringify) && fann[:immediate] %}
              immediate_names_\{{ivar.name}} = [\{{fann[:canonical]}}] of ::String
              \{% for alias_name in fann[:aliases] %}
                immediate_names_\{{ivar.name}} << \{{alias_name}}
              \{% end %}
              \{% if fann[:short] %}
                immediate_names_\{{ivar.name}} << \{{fann[:short]}}
              \{% end %}
              if pre_double_dash.any? { |dispatch_arg| immediate_names_\{{ivar.name}}.includes?(dispatch_arg) }
                \{% if fann[:immediate].is_a?(BoolLiteral) %}
                  \{% immediate_handler = "immediate_" + ivar.name.stringify %}
                \{% else %}
                  \{% immediate_handler = fann[:immediate].id.stringify %}
                \{% end %}
                immediate_inst_\{{ivar.name}} = new
                immediate_inst_\{{ivar.name}}.\{{ivar.name}} = true
                immediate_inst_\{{ivar.name}}.\{{immediate_handler.id}}
                return immediate_inst_\{{ivar.name}}
              end
            \{% end %}
          \{% end %}
          inst = parse(argv)
          inst.run_before_hooks
          inst.run
          inst
        rescue ex : ::Shell::AutoComplete::ParseError
          # `qualified` is already the full path from the root (parent_prefix was
          # threaded down), so the level that first raises seeds the whole path;
          # outer levels leave an already-set path untouched.
          ex.command_path ||= qualified
          raise ex
        rescue ex : ::ArgumentError
          new_err = ::Shell::AutoComplete::ParseError.new(ex.message || "argument error")
          new_err.command_path = qualified
          raise new_err
        end
      end
    end

    # Raw, ordered log of every flag occurrence matched during parse: the
    # spelling exactly as typed (dashes kept, aliases not canonicalized) and
    # the raw value consumed from argv or after `=`, or `nil` when none was
    # consumed (switches and forced-value shortcut flags). Positionals are not
    # logged — they preserve their own order. Empty until `parse` runs.
    property parsed_occurrences : Array({String, String?}) = [] of {String, String?}

    def run
      raise NotRunnable.new("#{self.class} must override #run")
    end
  end
end
