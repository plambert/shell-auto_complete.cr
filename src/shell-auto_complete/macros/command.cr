module Shell::AutoComplete
  macro command(type, **opts, &block)
    @[::Shell::AutoComplete::CommandDef({{opts.double_splat}})]
    class {{type.id}} < ::Shell::AutoComplete::Command
      {% if block %}{{ block.body }}{% end %}
    end
  end
end
