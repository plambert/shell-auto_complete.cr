module Shell::AutoComplete::Completion
  module Zsh
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
      script = String.build do |s|
        s << fn << "() {\n"
        s << "  local -a candidates\n"
        s << "  local IFS=$'\\n'\n"
        s << "  candidates=( $(" << cmd << ' '
        s << %q{"__complete" "$CURRENT" "${words[@]}" 2>/dev/null}
        s << ") )\n"
        s << "  compadd -- $candidates\n"
        s << "}\n"
        s << "compdef " << fn << ' ' << cmd << '\n'
      end
      script
    end
  end
end
