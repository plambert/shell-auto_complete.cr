module Shell::AutoComplete
  abstract class Command
    # Enables git-style external subcommands on a root command: when a
    # subcommand word matches no declared subcommand, PATH is searched for an
    # executable named `<command_name>-<word>`, and if found the current
    # process is replaced (`exec`) with it, passing every argument after the
    # subcommand word. No parameters are defined for the external command — it
    # is a blind handoff, so anything after the word (flags included) goes
    # through untouched.
    #
    # ```
    # Shell::AutoComplete.command Tool, name: "tool", description: "..." do
    #   external_subcommands
    #   subcommand Build
    # end
    #
    # # tool build ...   -> the declared Build subcommand
    # # tool deploy a b  -> exec's `tool-deploy a b` if found on PATH
    # ```
    #
    # Declared subcommands always win over the PATH lookup. A word containing a
    # path separator is never looked up (only a bare `tool-<word>` on PATH is),
    # and when nothing is found the usual `unknown subcommand` error is raised.
    #
    # `search_path:` restricts the lookup to a fixed, colon-separated list of
    # directories instead of `PATH`. A relative entry is resolved against the
    # directory holding the running binary (via `Process.executable_path`), so
    # `search_path: "commands:../lib/commands:/etc/tool/commands"` for a binary
    # at `/opt/tool/bin/tool` searches `/opt/tool/bin/commands`,
    # `/opt/tool/lib/commands`, and `/etc/tool/commands`, in that order,
    # regardless of the caller's `PATH`. Both the exec handoff and completion
    # use it.
    #
    # Only valid on a root command: declaring it on a `parent:`-derived command
    # is a compile error, since the executable name is built from one tool
    # prefix.
    macro external_subcommands(enabled = true, search_path = nil)
      {%
        raise "external_subcommands takes true or false (got #{enabled})" unless enabled.is_a?(BoolLiteral)
        if @type.superclass && @type.superclass.has_constant?("SUBCOMMANDS")
          raise "external_subcommands can only be declared on a root command; #{@type} derives from #{@type.superclass} via parent:"
        end
        unless search_path == nil || search_path.is_a?(StringLiteral)
          raise "external_subcommands search_path: must be a colon-separated string literal"
        end
      %}
      {% if enabled %}
        EXTERNAL_SUBCOMMANDS = true
        {% if search_path %}
          EXTERNAL_SUBCOMMANDS_SEARCH_PATH = {{ search_path }}
        {% end %}
      {% end %}
    end
  end
end
