module Shell::AutoComplete::Completion
  module Fish
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "__sac_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}_complete"
      script = String.build do |io|
        io << "function " << fn << '\n'
        io << "  set -l tokens (commandline -opc)\n"
        io << "  set -l current (commandline -ct)\n"
        io << "  " << cmd << ' '
        io << %q(__complete (count $tokens) $tokens $current 2>/dev/null)
        io << '\n'
        io << "end\n"
        io << "complete -c " << cmd << " -f -a \"(" << fn << ")\"\n"
      end
      script
    end
  end
end
