module Shell::AutoComplete
  abstract class Command
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
