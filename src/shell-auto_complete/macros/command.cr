module Shell::AutoComplete
  macro command(type, **opts, &block)
    @[::Shell::AutoComplete::CommandDef({{opts.double_splat}})]
    class {{type.id}} < ::Shell::AutoComplete::Command
      {% if block %}{{ block.body }}{% end %}
    end
  end

  abstract class Command
    # Override the default `--shell-completion` flag name for this command class.
    # Place this inside a `Shell::AutoComplete.command` block before any `flag`
    # declarations.
    macro shell_completion_flag(name)
      def self.shell_completion_flag_name : String
        {{ name }}
      end
    end
  end
end
