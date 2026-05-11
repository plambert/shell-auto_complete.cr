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

        reserved = ["--help", "-h"]
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
      %}

      @[::Shell::AutoComplete::FlagDef(
        canonical: {{ canonical }},
        aliases: {% if aliases.empty? %}[] of String{% else %}{{ aliases }}{% end %},
        short: {{ short_form }},
        description: {{ description }},
        negatable: {% if opts[:negatable] == nil %}true{% else %}{{ opts[:negatable] }}{% end %},
        transform_with: {{ opts[:transform_with] }},
      )]
      property {{ decl }}
    end
  end
end
