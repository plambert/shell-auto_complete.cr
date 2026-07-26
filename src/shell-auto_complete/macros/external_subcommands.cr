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
    # Only valid on a root command: declaring it on a `parent:`-derived command
    # is a compile error, since the executable name is built from one tool
    # prefix.
    macro external_subcommands(enabled = true)
      {%
        raise "external_subcommands takes true or false (got #{enabled})" unless enabled.is_a?(BoolLiteral)
        if @type.superclass && @type.superclass.has_constant?("SUBCOMMANDS")
          raise "external_subcommands can only be declared on a root command; #{@type} derives from #{@type.superclass} via parent:"
        end
      %}
      {% if enabled %}
        EXTERNAL_SUBCOMMANDS = true
      {% end %}
    end
  end
end
