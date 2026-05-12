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

        reserved = ["--help", "-h", "--shell-completion"]
        long_forms.each do |long_form|
          raw = long_form.id.stringify
          raise "#{raw} is a reserved flag name" if reserved.includes?(raw)
        end
        if short_form
          raw = short_form.id.stringify
          raise "#{raw} is a reserved flag name" if reserved.includes?(raw)
        end

        decl_type = decl.type
        if decl_type.is_a?(Union)
          non_nil_types = decl_type.types.reject { |type_node| type_node.resolve == Nil }
          if non_nil_types.size > 1 && opts[:transform_with] == nil
            raise "Union types require an explicit transform_with: on flag #{decl.var}"
          end
        end

        consumed_keys = [:transform_with, :validate_with, :negatable, :complete_with, :hidden, :shortcut_flags, :delimiter, :set_operations]
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
      )]
      {% if storage_remapped %}
        {% if decl_nullable %}
          property {{ decl.var }} : {{ storage_inner }}?
        {% else %}
          property {{ decl.var }} : {{ storage_inner }}
        {% end %}
      {% else %}
        property {{ decl }}
      {% end %}
    end
  end
end
