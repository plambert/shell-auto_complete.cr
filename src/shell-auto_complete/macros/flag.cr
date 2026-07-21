module Shell::AutoComplete
  abstract class Command
    macro flag(decl, *flag_strings, **opts)
      {%
        # Flatten positional args: expand any ArrayLiteral (e.g. %w(...)) in place.
        # This lets callers pass either:
        #   flag foo : String?, "--foo", "-f", "description"
        #   flag foo : String?, %w(--foo -f), "description"
        strings = [] of StringLiteral
        flag_strings.each do |arg|
          if arg.is_a?(ArrayLiteral)
            arg.each do |str|
              strings << str
            end
          else
            strings << arg
          end
        end

        long_forms = [] of StringLiteral
        short_form = nil
        description = nil
        placeholder = nil

        strings.each do |lit|
          if lit.is_a?(StringLiteral)
            raw = lit.id.stringify
            if raw.starts_with?("-") && raw.includes?(" ")
              # Embedded placeholder, callback-parser style: "--after TIME".
              # The flag name cannot contain a space, so the first space is an
              # unambiguous delimiter; the remainder is the placeholder.
              embedded_parts = raw.split(" ")
              embedded_placeholder = embedded_parts[1..-1].join(" ")
              if placeholder != nil && placeholder != embedded_placeholder
                raise "flag #{decl.var} declares more than one placeholder"
              end
              placeholder = embedded_placeholder
              raw = embedded_parts[0]
              lit = embedded_parts[0]
            end
            if raw.starts_with?("--")
              long_forms << lit
            elsif raw.starts_with?("-") && raw.size == 2
              raise "more than one short flag given" if short_form
              short_form = lit
            elsif description == nil && raw =~ /\A[A-Z][A-Z0-9:=\[\]_-]*\z/
              # Positional all-caps placeholder; must precede the description.
              raise "flag #{decl.var} declares more than one placeholder" if placeholder != nil
              placeholder = raw
            elsif description == nil
              description = lit
            else
              raise "unconsumed extra string literal #{lit} on flag #{decl.var} (placeholder and description already given)"
            end
          elsif lit.is_a?(Path)
            # Constant reference as the description (issue #18). Resolve at
            # macro-expansion time when the constant is a plain string
            # literal; otherwise splice the path so it resolves at render
            # time (covers computed/interpolated constants and constants
            # defined later).
            if description == nil
              resolved_description = lit.resolve?
              description = resolved_description.is_a?(StringLiteral) ? resolved_description : lit
            end
          elsif lit.is_a?(Call) && lit.args.empty? && lit.receiver.is_a?(Nop) && lit.block.is_a?(Nop)
            # Method reference as the description: resolves at help-render
            # time against a class method of the command.
            description = lit if description == nil
          else
            raise "flag-string args must be string literals, constant references, or method references; got #{lit.class_name}"
          end
        end

        # description: as a named option — same Path/Call/literal handling as
        # the positional form. A constant directly after the type declaration
        # does not parse (Crystal reads it as a type), so the named form is
        # the reliable spelling for constant descriptions.
        if description == nil && (named_description = opts[:description])
          if named_description.is_a?(Path)
            resolved_description = named_description.resolve?
            description = resolved_description.is_a?(StringLiteral) ? resolved_description : named_description
          else
            description = named_description
          end
        end
        if named_placeholder = opts[:placeholder]
          raise "flag #{decl.var} declares more than one placeholder" if placeholder != nil
          raise "placeholder: must be a string literal on flag #{decl.var}" unless named_placeholder.is_a?(StringLiteral)
          placeholder = named_placeholder.id.stringify
        end
        raise "no long flag given for #{decl}" if long_forms.empty?
        canonical = long_forms[0]
        aliases = long_forms.size > 1 ? long_forms[1..-1] : [] of StringLiteral
        description = description || ""

        # Build reserved list: always --help and -h; shell-completion flag is
        # configurable via `shell_completion_flag` macro (reads the constant set
        # by that macro, or falls back to the default "--shell-completion").
        if @type.has_constant?("SHELL_COMPLETION_FLAG")
          completion_reserved = @type.constant("SHELL_COMPLETION_FLAG")
        else
          completion_reserved = "--shell-completion"
        end
        reserved = ["--help", "-h", "--all-help", completion_reserved]
        long_forms.each do |long_form|
          raw = long_form.id.stringify
          raise "#{raw} is a reserved flag name" if reserved.includes?(raw)
        end
        if short_form
          raw = short_form.id.stringify
          raise "#{raw} is a reserved flag name" if reserved.includes?(raw)
        end

        decl_type = decl.type

        # Guard: shortcut_flags: is not valid for @[Flags] enums (which use
        # comma-separated values, not per-case boolean shortcuts). The option
        # is either `true` (every case) or a named-tuple config with `only:`,
        # `except:` (mutually exclusive case filters) and `aliases:` (extra
        # switches mapping to a specific case, e.g. {quiet: :warn}).
        sc_conf = opts[:shortcut_flags]
        if sc_conf
          if decl_type.is_a?(Union)
            sc_non_nil = decl_type.types.reject { |type_node| type_node.resolve == Nil }
            sc_resolved = sc_non_nil.size == 1 ? sc_non_nil[0].resolve : nil
          else
            sc_resolved = decl_type.resolve
          end
          if sc_resolved && sc_resolved.annotation(::Flags)
            raise "shortcut_flags: is not valid for @[Flags] enums (flag #{decl.var})"
          end
          unless sc_conf.is_a?(BoolLiteral) || sc_conf.is_a?(NamedTupleLiteral)
            raise "shortcut_flags: must be true or a named-tuple config ({only:/except:/aliases:}) on flag #{decl.var}"
          end
          if sc_conf.is_a?(NamedTupleLiteral)
            sc_conf.keys.each do |conf_key|
              unless ["only", "except", "aliases"].includes?(conf_key.stringify)
                raise "unknown shortcut_flags option #{conf_key} on flag #{decl.var} (expected only:, except:, aliases:)"
              end
            end
            if sc_conf[:only] && sc_conf[:except]
              raise "shortcut_flags only: and except: are mutually exclusive on flag #{decl.var}"
            end
            if sc_resolved
              sc_valid_cases = sc_resolved.constants.map(&.stringify.underscore)
              (sc_conf[:only] || [] of SymbolLiteral).each do |case_sym|
                unless sc_valid_cases.includes?(case_sym.id.stringify)
                  raise "shortcut_flags only: names unknown enum case #{case_sym} on flag #{decl.var}"
                end
              end
              (sc_conf[:except] || [] of SymbolLiteral).each do |case_sym|
                unless sc_valid_cases.includes?(case_sym.id.stringify)
                  raise "shortcut_flags except: names unknown enum case #{case_sym} on flag #{decl.var}"
                end
              end
              if sc_aliases_check = sc_conf[:aliases]
                sc_aliases_check.keys.each do |alias_key|
                  target_sym = sc_aliases_check[alias_key]
                  unless sc_valid_cases.includes?(target_sym.id.stringify)
                    raise "shortcut_flags alias #{alias_key}: names unknown enum case #{target_sym} on flag #{decl.var}"
                  end
                end
              end
            end
          end
        end

        if decl_type.is_a?(Union)
          non_nil_types = decl_type.types.reject { |type_node| type_node.resolve == Nil }
          if non_nil_types.size > 1 && opts[:transform_with] == nil
            raise "Union types require an explicit transform_with: on flag #{decl.var}"
          end
        end

        # hash_operations: false makes the bare `-key` delete form a parse
        # error on this flag (issue #20) — useful when deletion is
        # meaningless and a `-foo` typo of `foo=...` should be loud.
        if opts.keys.map(&.stringify).includes?("hash_operations")
          unless decl_type.id.stringify.gsub(/\A::/, "").starts_with?("Hash(")
            raise "hash_operations: is only valid on Hash flags (flag #{decl.var})"
          end
        end

        # Collection flags must state their splitting behavior explicitly
        # (issue #17). A comma-split default silently corrupts values whose
        # data legally contains commas (paths, regexes, URLs, titles), so the
        # author must choose: delimiter: "," to split each value, or
        # delimiter: nil to take each occurrence as one element.
        decl_type_base = decl_type.id.stringify.gsub(/\A::/, "").split("(")[0]
        if ["Array", "Set"].includes?(decl_type_base) && !opts.keys.map(&.stringify).includes?("delimiter")
          raise "collection flag #{decl.var} must state its splitting behavior: pass delimiter: \",\" (split each value on commas) or delimiter: nil (each occurrence is one element)"
        end

        # immediate: marks a print-reference-data-and-exit switch (issue
        # #21): dispatch invokes the designated handler as soon as the
        # spelling appears (before full-line validation). `immediate: true`
        # uses the convention `immediate_<flag name>`; a symbol names the
        # handler method explicitly.
        if opts[:immediate]
          unless decl_is_switch_pre = (decl_type.id.stringify.gsub(/\A::/, "") == "Bool" || (decl_type.is_a?(Union) && decl_type.types.reject { |type_node| type_node.resolve == Nil }.size == 1 && decl_type.types.reject { |type_node| type_node.resolve == Nil }[0].resolve == Bool))
            raise "immediate: is only valid on switch (Bool/Bool?) flags (flag #{decl.var})"
          end
          unless opts[:immediate].is_a?(BoolLiteral) || opts[:immediate].is_a?(SymbolLiteral)
            raise "immediate: must be true or a symbol naming the handler method (flag #{decl.var})"
          end
        end

        # group: places the flag under its own heading in help (issue #21).
        if (group_opt = opts[:group]) && !group_opt.is_a?(StringLiteral) && !group_opt.is_a?(Path)
          raise "group: must be a string literal or constant reference (flag #{decl.var})"
        end
        if group_opt.is_a?(Path)
          resolved_group = group_opt.resolve?
          group_opt = resolved_group if resolved_group.is_a?(StringLiteral)
        end

        # ---- duplicate-name detection (issue #10) ----
        # Collect every spelling this declaration produces, including generated
        # `--no-` negations and enum shortcut switches, and check them against
        # the per-command registry. `override: true` replaces the prior owning
        # flag wholesale: its registry entries are tombstoned and its property
        # is recorded so the generators skip it.
        produced_names = [] of String
        long_forms.each do |long_form|
          produced_names << long_form.id.stringify
        end
        produced_names << short_form.id.stringify if short_form
        negatable_opt = opts[:negatable] == nil ? true : opts[:negatable]
        # Bool and Bool? are both switches; every long form (canonical and
        # aliases) gets a generated `--no-` negation.
        switch_non_nil = decl_type.is_a?(Union) ? decl_type.types.reject { |type_node| type_node.resolve == Nil } : [decl_type]
        decl_is_switch = switch_non_nil.size == 1 && switch_non_nil[0].resolve == Bool
        if decl_is_switch && negatable_opt
          long_forms.each do |long_form|
            produced_names << "--no-" + long_form.id.stringify.gsub(/\A--/, "")
          end
        end
        if sc_conf && sc_resolved
          sc_only = sc_conf.is_a?(NamedTupleLiteral) ? sc_conf[:only] : nil
          sc_except = sc_conf.is_a?(NamedTupleLiteral) ? sc_conf[:except] : nil
          # Two constants may kebab-case to the same switch spelling (KB and
          # Kb both give --kb). When they hold the same value they are alias
          # constants: the first-declared one owns the switch and later ones
          # are skipped everywhere. When the values differ the switch would be
          # ambiguous, so fail here (once, at the declaration site) with the
          # fix spelled out.
          sc_seen_kebabs = [] of StringLiteral
          sc_seen_consts = [] of MacroId
          sc_resolved.constants.each do |case_const|
            case_under = case_const.stringify.underscore
            sc_included = sc_only ? sc_only.any? { |case_sym| case_sym.id.stringify == case_under } : (sc_except ? !sc_except.any? { |case_sym| case_sym.id.stringify == case_under } : true)
            if sc_included
              case_kebab = case_under.tr("_", "-")
              first_idx = nil
              (0...sc_seen_kebabs.size).each do |seen_idx|
                first_idx = seen_idx if first_idx == nil && sc_seen_kebabs[seen_idx] == case_kebab
              end
              if first_idx == nil
                sc_seen_kebabs << case_kebab
                sc_seen_consts << case_const
                produced_names << "--" + case_kebab
              elsif sc_resolved.constant(case_const) != sc_resolved.constant(sc_seen_consts[first_idx])
                raise "shortcut_flags on flag #{decl.var}: enum constants #{sc_seen_consts[first_idx]} and #{case_const} both produce the switch --#{case_kebab.id} but have different values; exclude one by adding shortcut_flags: {except: [:#{case_under.id}]} (the except: list takes underscored case names as symbols)"
              end
            end
          end
          if sc_conf.is_a?(NamedTupleLiteral) && (sc_aliases_reg = sc_conf[:aliases])
            sc_aliases_reg.keys.each do |alias_key|
              produced_names << "--" + alias_key.stringify.underscore.tr("_", "-")
            end
          end
        end

        reg_names = @type.constant("FLAG_REGISTRY_NAMES")
        reg_owners = @type.constant("FLAG_REGISTRY_OWNERS")
        overridden_ivars = @type.constant("OVERRIDDEN_FLAG_IVARS")
        var_name = decl.var.stringify

        if opts[:override]
          prior_owners = [] of String
          produced_names.each do |produced|
            (0...reg_names.size).each do |reg_idx|
              if reg_names[reg_idx] == produced && !prior_owners.includes?(reg_owners[reg_idx])
                prior_owners << reg_owners[reg_idx]
              end
            end
          end
          if prior_owners.empty?
            raise "flag #{decl.var} has `override: true` but none of its names (#{produced_names.map(&.id).join(", ")}) match an existing flag on #{@type}"
          end
          if prior_owners.includes?(var_name)
            raise "flag #{decl.var} overrides the flag bound to the same property; an overriding flag must use a new property name (the replaced property remains declared but is no longer bound)"
          end
          (0...reg_names.size).each do |reg_idx|
            if prior_owners.includes?(reg_owners[reg_idx])
              reg_names[reg_idx] = ""
              reg_owners[reg_idx] = ""
            end
          end
          prior_owners.each do |prior_owner|
            overridden_ivars << prior_owner unless overridden_ivars.includes?(prior_owner)
          end
        end

        produced_names.each do |produced|
          (0...reg_names.size).each do |reg_idx|
            if reg_names[reg_idx] == produced
              raise "duplicate flag name #{produced.id} on #{@type}: already declared by flag `#{reg_owners[reg_idx].id}`; add `override: true` to replace the existing flag"
            end
          end
          reg_names << produced
          reg_owners << var_name
        end

        consumed_keys = [:description, :placeholder, :group, :immediate, :transform_with, :validate_with, :negatable, :complete_with, :hidden, :shortcut_flags, :delimiter, :set_operations, :hash_operations, :override]
        forwarded_pairs = [] of StringLiteral
        opts.each do |opt_key, opt_val|
          next if consumed_keys.includes?(opt_key)
          forwarded_pairs << "#{opt_key}: #{opt_val}"
        end

        # Resolve the storage type: if __arg_transform returns a different base type
        # than the declared type (e.g. File -> Path, Dir -> Path), use the
        # return type of __arg_transform as the property storage type.
        # We compare base names (before any generic params) so that Array(T) -> Array(T)
        # is correctly treated as non-remapped even though strings differ.
        decl_nullable = decl_type.is_a?(Union)
        decl_inner = decl_nullable ? decl_type.types.reject { |type_node| type_node.resolve == Nil }[0] : decl_type
        storage_inner = decl_inner
        if decl_inner.resolve.class.methods.any? { |meth| meth.name.stringify == "__arg_transform" }
          decl_inner.resolve.class.methods.each do |meth|
            if meth.name.stringify == "__arg_transform"
              storage_inner = meth.return_type
            end
          end
        end
        decl_base = decl_inner.id.stringify.split("(")[0].gsub(/\A::/, "")
        storage_base = storage_inner.id.stringify.split("(")[0].gsub(/\A::/, "")
        storage_remapped = decl_base != storage_base
        # A remapped storage type comes from the transformer's own source file
        # (its __arg_transform return type), so it must be spliced fully
        # qualified — the user's namespace may shadow it (issue #9).
        storage_inner_q = (storage_inner.stringify.starts_with?("::") || storage_inner.stringify.starts_with?("(")) ? storage_inner : "::#{storage_inner}".id

        # ---- value placeholder (issue #19) ----
        # When no placeholder was given, derive one from the declared type so
        # every value flag's help line shows what it consumes. Switches get
        # none (and explicitly giving one is an error).
        if placeholder != nil && decl_is_switch
          raise "switch flag #{decl.var} cannot take a placeholder"
        end
        if placeholder == nil && !decl_is_switch
          choices_opt = opts[:choices]
          if choices_opt.is_a?(ArrayLiteral) && choices_opt.size <= 4 && choices_opt.size > 0
            placeholder = choices_opt.map(&.id.stringify).join("|")
          elsif decl_base == "Hash"
            placeholder = "KEY=VALUE"
          else
            if ["Array", "Set"].includes?(decl_base) && decl_inner.is_a?(Generic)
              ph_type = decl_inner.type_vars[0]
            else
              ph_type = decl_inner
            end
            ph_base = ph_type.id.stringify.gsub(/\A::/, "").split("(")[0].split("::")[-1]
            ph_enum_cases = nil
            if ph_type.is_a?(Path)
              ph_resolved = ph_type.resolve?
              if ph_resolved.is_a?(TypeNode) && ph_resolved < ::Enum
                # uniq: alias constants (KB = 1024, Kb = 1024) kebab-case to
                # the same spelling; show it once.
                ph_enum_cases = ph_resolved.constants.map(&.stringify.underscore.tr("_", "-")).uniq
              end
            end
            if ph_enum_cases
              placeholder = ph_enum_cases.size <= 4 ? ph_enum_cases.join("|") : ph_base.upcase
            elsif ["Int8", "Int16", "Int32", "Int64", "Int128", "UInt8", "UInt16", "UInt32", "UInt64", "UInt128", "BigInt", "PositiveInt", "NonNegativeInt", "Percentage"].includes?(ph_base)
              placeholder = "NUMBER"
            elsif ["Float32", "Float64", "BigFloat"].includes?(ph_base)
              placeholder = "FLOAT"
            elsif ph_base == "String"
              placeholder = "TEXT"
            elsif ph_base == "Path"
              placeholder = "PATH"
            elsif ph_base == "File"
              placeholder = "FILE"
            elsif ["Dir", "DirPath"].includes?(ph_base)
              placeholder = "DIR"
            elsif ph_base == "URI"
              placeholder = "URL"
            elsif ["Time", "EpochTime"].includes?(ph_base)
              placeholder = "TIME"
            elsif ph_base == "Date"
              placeholder = "DATE"
            elsif ph_base == "Regex"
              placeholder = "REGEX"
            elsif ph_base == "Char"
              placeholder = "CHAR"
            else
              placeholder = "VALUE"
            end
          end
        end
      %}

      @[::Shell::AutoComplete::FlagDef(
        canonical: {{ canonical }},
        aliases: {% if aliases.empty? %}[] of String{% else %}{{ aliases }}{% end %},
        short: {{ short_form }},
        description: {{ description }},
        negatable: {% if opts[:negatable] == nil %}true{% else %}{{ opts[:negatable] }}{% end %},
        hidden: {% if opts[:hidden] == nil %}false{% else %}{{ opts[:hidden] }}{% end %},
        transform_with: {{ opts[:transform_with] }},
        validate_with: {{ opts[:validate_with] }},
        shortcut_flags: {% if opts[:shortcut_flags] %}{{ opts[:shortcut_flags] }}{% else %}false{% end %},
        set_operations: {% if opts[:set_operations] %}true{% else %}false{% end %},
        hash_operations: {% if opts[:hash_operations] == nil %}true{% else %}{{ opts[:hash_operations] }}{% end %},
        delimiter: {% if opts.keys.map(&.stringify).includes?("delimiter") %}{{ opts[:delimiter] }}{% else %}","{% end %},
        forwarded_opts: {% if forwarded_pairs.empty? %}NamedTuple.new{% else %}{ {{ forwarded_pairs.join(", ").id }} }{% end %},
        transformer_type: {% if storage_remapped %}{{ decl_inner }}{% else %}nil{% end %},
        complete_with: {{ opts[:complete_with] }},
        placeholder: {% if placeholder %}{{ placeholder }}{% else %}nil{% end %},
        group: {% if group_opt %}{{ group_opt }}{% else %}nil{% end %},
        immediate: {{ opts[:immediate] }},
      )]
      {% if storage_remapped %}
        {% if decl_nullable %}
          property {{ decl.var }} : {{ storage_inner_q }}?
        {% else %}
          property {{ decl.var }} : {{ storage_inner_q }}
        {% end %}
      {% else %}
        property {{ decl }}
      {% end %}
    end
  end
end
