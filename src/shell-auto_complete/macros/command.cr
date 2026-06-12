module Shell::AutoComplete
  # Defines a command class. `parent:` names another command class to inherit
  # from (issue #22): the new command gains every flag the parent declares —
  # properties, parsing, help (under an "Inherited options" heading), and
  # completion — and may redeclare one with `override: true`. Routing is
  # still declared separately with `subcommand` on the parent, so inheritance
  # and routing compose but neither implies the other.
  macro command(type, **opts, &block)
    @[::Shell::AutoComplete::CommandDef({{ opts.double_splat }})]
    class {{ type.id }} < {% if opts[:parent] %}{{ opts[:parent] }}{% else %}::Shell::AutoComplete::Command{% end %}
      {% if block %}{{ block.body }}{% end %}
    end
  end

  abstract class Command
    # Override the default `--shell-completion` flag name for this command class.
    # Place this inside a `Shell::AutoComplete.command` block before any `flag`
    # declarations.
    macro shell_completion_flag(name)
      SHELL_COMPLETION_FLAG = {{ name }}

      def self.shell_completion_flag_name : String
        {{ name }}
      end
    end
  end
end
