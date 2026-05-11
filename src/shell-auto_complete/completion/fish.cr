module Shell::AutoComplete::Completion
  module Fish
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "__sac_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}_complete"
      script = String.build do |s|
        s << "function " << fn << '\n'
        s << "  set -l tokens (commandline -opc)\n"
        s << "  set -l current (commandline -ct)\n"
        s << "  " << cmd << ' '
        s << %q{__complete (count $tokens) $tokens $current 2>/dev/null}
        s << '\n'
        s << "end\n"
        s << "complete -c " << cmd << " -f -a \"(" << fn << ")\"\n"
      end
      script
    end
  end
end
