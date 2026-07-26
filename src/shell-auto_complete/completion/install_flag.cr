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

      # `--absolute`/`-a`: bake the running binary's absolute path into the
      # callback, so the completion invokes this exact executable rather than
      # whichever one `PATH` resolves — handy for testing a dev build. The
      # command name still registers the completion.
      extra = argv[2]?
      if extra && !["--absolute", "-a"].includes?(extra)
        stderr.puts "Unknown option: #{extra} (expected --absolute or -a)"
        return true
      end
      executable = extra ? (::Process.executable_path || PROGRAM_NAME) : nil

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
      stdout.print klass.completion_script(shell_sym, executable)
      true
    end
  end
end
