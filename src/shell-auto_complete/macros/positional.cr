module Shell::AutoComplete
  abstract class Command
    macro positionals(decl, *strings, **opts)
      {%
        decl_type = decl.type
        type_str = decl_type.stringify
        unless type_str.starts_with?("Array(") || type_str.starts_with?("Set(") || type_str.starts_with?("Hash(")
          raise "positionals type must be Array(T), Set(T), or Hash(String, T), got #{type_str}"
        end

        description = nil
        strings.each do |lit|
          raise "positionals args must be string literals" unless lit.is_a?(StringLiteral)
          description = lit if description == nil
        end
        raise "positionals requires a description" unless description

        consumed_keys = [:min, :max, :transform_with, :validate_with, :complete_with, :hidden]
        forwarded_pairs = [] of String
        opts.each do |opt_key, opt_val|
          next if consumed_keys.includes?(opt_key)
          forwarded_pairs << "#{opt_key}: #{opt_val}"
        end
      %}

      # Guard: at most one positionals per command (detected via sentinel method)
      {% if @type.methods.any? { |meth| meth.name.stringify == "__has_positionals_sentinel__" } %}
        \{{ raise "#{@type} already has a positionals declaration; at most one is allowed" }}
      {% end %}

      private def __has_positionals_sentinel__ : Nil
      end

      @[::Shell::AutoComplete::PositionalsDef(
        description: {{ description }},
        min: {% if opts[:min] == nil %}0{% else %}{{ opts[:min] }}{% end %},
        max: {% if opts[:max] == nil %}Int32::MAX{% else %}{{ opts[:max] }}{% end %},
        transform_with: {{ opts[:transform_with] }},
        validate_with: {{ opts[:validate_with] }},
        complete_with: {{ opts[:complete_with] }},
        hidden: {% if opts[:hidden] == nil %}false{% else %}{{ opts[:hidden] }}{% end %},
        forwarded_opts: {% if forwarded_pairs.empty? %}NamedTuple.new{% else %}{ {{ forwarded_pairs.join(", ").id }} }{% end %},
      )]
      property {{ decl }} = {{ decl.type }}.new
    end

    macro positional(decl, *strings, **opts)
      {%
        description = nil
        strings.each do |lit|
          raise "positional args must be string literals" unless lit.is_a?(StringLiteral)
          description = lit if description == nil
        end
        raise "positional requires a description" unless description

        consumed_keys = [:transform_with, :validate_with, :complete_with, :hidden]
        forwarded_pairs = [] of String
        opts.each do |k, v|
          next if consumed_keys.includes?(k)
          forwarded_pairs << "#{k}: #{v}"
        end
      %}

      # Guard: positional cannot coexist with subcommands
      {% if @type.methods.any? { |meth| meth.name.stringify == "__has_subcommands_sentinel__" } %}
        \{{ raise "#{@type} declares both positionals and subcommands, which is not allowed" }}
      {% end %}

      @[::Shell::AutoComplete::PositionalDef(
        description: {{ description }},
        transform_with: {{ opts[:transform_with] }},
        validate_with: {{ opts[:validate_with] }},
        complete_with: {{ opts[:complete_with] }},
        hidden: {% if opts[:hidden] == nil %}false{% else %}{{ opts[:hidden] }}{% end %},
        required: {% if decl.type.is_a?(Union) && decl.type.types.any? { |t| t.resolve == Nil } %}false{% else %}true{% end %},
        forwarded_opts: {% if forwarded_pairs.empty? %}NamedTuple.new{% else %}{ {{ forwarded_pairs.join(", ").id }} }{% end %},
      )]
      {% if decl.type.is_a?(Union) && decl.type.types.any? { |t| t.resolve == Nil } %}
        property {{ decl }}
      {% else %}
        property! {{ decl }}
      {% end %}
    end
  end
end
