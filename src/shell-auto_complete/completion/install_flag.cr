module Shell::AutoComplete::Completion
  module InstallFlag
    SHELLS = %w[bash zsh fish]

    # Checks whether *argv* begins with the configured shell-completion flag for
    # *klass*.  If so, handles the request (writing to *stdout* or *stderr* as
    # appropriate) and returns `true`; the caller should not run normal dispatch.
    # Returns `false` when the flag is absent, meaning normal dispatch should
    # proceed.
    def self.handle(klass : ::Shell::AutoComplete::Command.class, argv : Array(String), stdout : IO, stderr : IO) : Bool
      flag_name = klass.shell_completion_flag_name
      return false unless argv.first? == flag_name

      shell = argv[1]?
      unless shell && SHELLS.includes?(shell)
        stderr.puts "Supported shells: #{SHELLS.join(", ")}"
        stderr.puts %(Example: eval "$(#{klass.command_name} #{flag_name} bash)")
        return true
      end

      if stdout.responds_to?(:tty?) && stdout.tty?
        stderr.puts %(Add this to your shell rc: eval "$(#{klass.command_name} #{flag_name} #{shell})")
        return true
      end

      shell_sym = case shell
                  when "bash" then :bash
                  when "zsh"  then :zsh
                  when "fish" then :fish
                  else             raise "unreachable"
                  end
      stdout.print klass.completion_script(shell_sym)
      true
    end
  end
end
