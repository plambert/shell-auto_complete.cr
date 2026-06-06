module Shell::AutoComplete::Completion
  module Fish
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "__sac_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}_complete"
      script = String.build do |io|
        io << "function " << fn << '\n'
        io << "  set -l tokens (commandline -opc)\n"
        io << "  set -l current (commandline -ct)\n"
        io << "  set -l out (" << cmd << ' '
        io << %q(__complete (count $tokens) $tokens $current 2>/dev/null)
        io << ")\n"
        io << "  if test (count $out) -eq 1\n"
        io << "    switch $out[1]\n"
        io << "      case " << Directive::FILES << '\n'
        io << "        __fish_complete_path $current\n"
        io << "        return\n"
        io << "      case " << Directive::DIRS << '\n'
        io << "        __fish_complete_directories $current\n"
        io << "        return\n"
        io << "    end\n"
        io << "  end\n"
        io << "  for line in $out\n"
        io << "    echo $line\n"
        io << "  end\n"
        io << "end\n"
        io << "complete -c " << cmd << " -f -a \"(" << fn << ")\"\n"
      end
      script
    end
  end
end
