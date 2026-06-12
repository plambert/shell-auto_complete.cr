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

        strings.each do |lit|
          unless lit.is_a?(StringLiteral)
            raise "flag-string args must be string literals; got #{lit.class_name}"
          end
          raw = lit.id.stringify
          if raw.starts_with?("--")
            long_forms << lit
          elsif raw.starts_with?("-") && raw.size == 2
            raise "more than one short flag given" if short_form
            short_form = lit
          else
            description = lit if description == nil
          end
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

        # Guard: shortcut_flags: true is not valid for @[Flags] enums (which use
        # comma-separated values, not per-case boolean shortcuts).
        if opts[:shortcut_flags]
          if decl_type.is_a?(Union)
            sc_non_nil = decl_type.types.reject { |type_node| type_node.resolve == Nil }
            sc_resolved = sc_non_nil.size == 1 ? sc_non_nil[0].resolve : nil
          else
            sc_resolved = decl_type.resolve
          end
          if sc_resolved && sc_resolved.annotation(::Flags)
            raise "shortcut_flags: true is not valid for @[Flags] enums (flag #{decl.var})"
          end
        end

        if decl_type.is_a?(Union)
          non_nil_types = decl_type.types.reject { |type_node| type_node.resolve == Nil }
          if non_nil_types.size > 1 && opts[:transform_with] == nil
            raise "Union types require an explicit transform_with: on flag #{decl.var}"
          end
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
        if opts[:shortcut_flags] && sc_resolved
          sc_resolved.constants.each do |case_const|
            produced_names << "--" + case_const.stringify.underscore.tr("_", "-")
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

        consumed_keys = [:transform_with, :validate_with, :negatable, :complete_with, :hidden, :shortcut_flags, :delimiter, :set_operations, :override]
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
        decl_base = decl_inner.id.stringify.split("(")[0]
        storage_base = storage_inner.id.stringify.split("(")[0]
        storage_remapped = decl_base != storage_base
        # A remapped storage type comes from the transformer's own source file
        # (its __arg_transform return type), so it must be spliced fully
        # qualified — the user's namespace may shadow it (issue #9).
        storage_inner_q = (storage_inner.stringify.starts_with?("::") || storage_inner.stringify.starts_with?("(")) ? storage_inner : "::#{storage_inner}".id
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
        shortcut_flags: {% if opts[:shortcut_flags] %}true{% else %}false{% end %},
        set_operations: {% if opts[:set_operations] %}true{% else %}false{% end %},
        delimiter: {% if opts.keys.map(&.stringify).includes?("delimiter") %}{{ opts[:delimiter] }}{% else %}","{% end %},
        forwarded_opts: {% if forwarded_pairs.empty? %}NamedTuple.new{% else %}{ {{ forwarded_pairs.join(", ").id }} }{% end %},
        transformer_type: {% if storage_remapped %}{{ decl_inner }}{% else %}nil{% end %},
        complete_with: {{ opts[:complete_with] }},
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
