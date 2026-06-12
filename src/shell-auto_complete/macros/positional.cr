module Shell::AutoComplete
  abstract class Command
    macro positionals(decl, *strings, **opts)
      {%
        decl_type = decl.type
        type_str = decl_type.stringify

        # SetDelta is a special variadic type: its tokens (`+name` / `-name` /
        # `name`) are merged into a single Hash(String, Bool) rather than
        # collected element-by-element.
        set_delta = decl_type.resolve.stringify == "Shell::AutoComplete::Types::SetDelta"

        unless set_delta || type_str.starts_with?("Array(") || type_str.starts_with?("Set(")
          if type_str.starts_with?("Hash(")
            raise "Hash positionals are not supported; use Shell::AutoComplete::Types::SetDelta for +name/-name deltas, or Array(T)/Set(T)"
          end
          raise "positionals type must be Array(T), Set(T), or Shell::AutoComplete::Types::SetDelta, got #{type_str}"
        end

        description = nil
        strings.each do |lit|
          if lit.is_a?(StringLiteral)
            description = lit if description == nil
          elsif lit.is_a?(Path)
            if description == nil
              resolved_description = lit.resolve?
              description = resolved_description.is_a?(StringLiteral) ? resolved_description : lit
            end
          elsif lit.is_a?(Call) && lit.args.empty? && lit.receiver.is_a?(Nop) && lit.block.is_a?(Nop)
            description = lit if description == nil
          else
            raise "positionals args must be string literals, constant references, or method references; got #{lit.class_name}"
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
        raise "positionals requires a description" unless description

        consumed_keys = [:description, :min, :max, :transform_with, :validate_with, :complete_with, :hidden]
        forwarded_pairs = [] of String
        opts.each do |opt_key, opt_val|
          next if consumed_keys.includes?(opt_key)
          forwarded_pairs << "#{opt_key}: #{opt_val}"
        end

        if set_delta
          # The bound value is the merged delta.
          storage_collection = "::Hash(::String, ::Bool)"
          elem_remapped = false
          pos_elem_type = nil
        else
          # Resolve the element storage type: if the declared element type's
          # __arg_transform returns a different base type (e.g. File/Dir -> Path),
          # store the collection over that return type and record the declared
          # element type so the parser/completer dispatch through it. Mirrors the
          # scalar positional / flag macros.
          container_base = type_str.split("(")[0]
          pos_elem_type = decl_type.type_vars[0]
          storage_elem = pos_elem_type
          if pos_elem_type.resolve.class.methods.any? { |meth| meth.name.stringify == "__arg_transform" }
            pos_elem_type.resolve.class.methods.each do |meth|
              storage_elem = meth.return_type if meth.name.stringify == "__arg_transform"
            end
          end
          elem_base = pos_elem_type.id.stringify.split("(")[0].gsub(/\A::/, "")
          storage_elem_base = storage_elem.id.stringify.split("(")[0].gsub(/\A::/, "")
          elem_remapped = elem_base != storage_elem_base
          # A remapped element type comes from the transformer's source file, so
          # qualify it against the user's namespace (issue #9). A non-remapped
          # element resplices the user's own spelling (NOT the transformer's
          # return-type node, which may be unqualified) — it may be a path
          # relative to their namespace.
          storage_elem = pos_elem_type unless elem_remapped
          storage_elem_str = storage_elem.stringify
          if elem_remapped && !(storage_elem_str.starts_with?("::") || storage_elem_str.starts_with?("("))
            storage_elem_str = "::" + storage_elem_str
          end
          storage_collection = container_base + "(" + storage_elem_str + ")"
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
        transformer_type: {% if elem_remapped %}{{ pos_elem_type }}{% else %}nil{% end %},
        set_delta: {{ set_delta }},
        forwarded_opts: {% if forwarded_pairs.empty? %}NamedTuple.new{% else %}{ {{ forwarded_pairs.join(", ").id }} }{% end %},
      )]
      property {{ decl.var }} : {{ storage_collection.id }} = {{ storage_collection.id }}.new
    end

    macro positional(decl, *strings, **opts)
      {%
        description = nil
        strings.each do |lit|
          if lit.is_a?(StringLiteral)
            description = lit if description == nil
          elsif lit.is_a?(Path)
            if description == nil
              resolved_description = lit.resolve?
              description = resolved_description.is_a?(StringLiteral) ? resolved_description : lit
            end
          elsif lit.is_a?(Call) && lit.args.empty? && lit.receiver.is_a?(Nop) && lit.block.is_a?(Nop)
            description = lit if description == nil
          else
            raise "positional args must be string literals, constant references, or method references; got #{lit.class_name}"
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
        raise "positional requires a description" unless description

        consumed_keys = [:description, :transform_with, :validate_with, :complete_with, :hidden]
        forwarded_pairs = [] of String
        opts.each do |key, value|
          next if consumed_keys.includes?(key)
          forwarded_pairs << "#{key}: #{value}"
        end

        # Resolve the storage type: if the declared type's __arg_transform returns
        # a different base type (e.g. File/Dir -> Path), store the property as that
        # return type and record the declared type so the parser/completer still
        # dispatch through it. Mirrors the flag macro.
        decl_nullable = decl.type.is_a?(Union)
        decl_inner = decl_nullable ? decl.type.types.reject { |type_node| type_node.resolve == Nil }[0] : decl.type
        storage_inner = decl_inner
        if decl_inner.resolve.class.methods.any? { |meth| meth.name.stringify == "__arg_transform" }
          decl_inner.resolve.class.methods.each do |meth|
            storage_inner = meth.return_type if meth.name.stringify == "__arg_transform"
          end
        end
        decl_base = decl_inner.id.stringify.split("(")[0].gsub(/\A::/, "")
        storage_base = storage_inner.id.stringify.split("(")[0].gsub(/\A::/, "")
        storage_remapped = decl_base != storage_base
        # A remapped storage type comes from the transformer's source file, so
        # qualify it against the user's namespace (issue #9). A non-remapped
        # one resplices the user's own spelling (NOT the transformer's
        # return-type node, which may be unqualified).
        if storage_remapped
          unless storage_inner.stringify.starts_with?("::") || storage_inner.stringify.starts_with?("(")
            storage_inner = "::#{storage_inner}".id
          end
        else
          storage_inner = decl_inner
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
        required: {% if decl_nullable %}false{% else %}true{% end %},
        transformer_type: {% if storage_remapped %}{{ decl_inner }}{% else %}nil{% end %},
        forwarded_opts: {% if forwarded_pairs.empty? %}NamedTuple.new{% else %}{ {{ forwarded_pairs.join(", ").id }} }{% end %},
      )]
      {% if decl_nullable %}
        property {{ decl.var }} : {{ storage_inner }}?
      {% else %}
        property! {{ decl.var }} : {{ storage_inner }}
      {% end %}
    end
  end
end
