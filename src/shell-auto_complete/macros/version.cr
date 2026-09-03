module Shell::AutoComplete
  abstract class Command
    # Sets the program name shown by `--version` (and the `version`
    # subcommand). Defaults to the command's name, which itself defaults to
    # the basename of `PROGRAM_NAME`. Read back via `.version_name`.
    macro tool_name(name)
      {% raise "tool_name must be a string literal" unless name.is_a?(StringLiteral) %}
      TOOL_NAME = {{ name }}
    end

    # Sets the version string shown by `--version` (and the `version`
    # subcommand), e.g. `tool_version "1.0.0"`. When not set, the nearest
    # `VERSION` constant visible from the command class (the class itself,
    # its enclosing namespaces, the top level, or an inherited command) is
    # used; failing that, `Shell::AutoComplete::SHARDS_PROJECT_VERSION`, the
    # compiling project's version captured once at compile time. Read back via
    # `.version_string`.
    macro tool_version(version)
      {% raise "tool_version must be a string literal" unless version.is_a?(StringLiteral) %}
      TOOL_VERSION = {{ version }}
    end

    # Disables the automatic `--version` intercept for this command (and,
    # via inheritance, its `parent:`-derived subcommands). Declaring a flag
    # that claims the `--version` spelling disables the intercept on its own;
    # this macro is for turning it off without claiming the spelling.
    macro disable_version_flag
      VERSION_FLAG_DISABLED = true
    end

    # Adds a `version` subcommand that prints the same `<name> <version>`
    # line as the `--version` flag.
    macro enable_version_subcommand
      @[::Shell::AutoComplete::CommandDef(name: "version", description: "Print the program name and version")]
      class VersionSubcommand < ::Shell::AutoComplete::Command
        def run
          puts {{ @type }}.version_name + " " + {{ @type }}.version_string
        end
      end

      subcommand VersionSubcommand
    end
  end
end
