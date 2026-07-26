module Shell::AutoComplete::Completion
  module Zsh
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
      script = String.build do |io|
        io << fn << "() {\n"
        io << "  local -a candidates\n"
        io << "  local IFS=$'\\n'\n"
        io << "  candidates=( $(" << cmd << ' '
        io << %q("__complete" "$CURRENT" "${words[@]}" 2>/dev/null)
        io << ") )\n"
        io << "  if (( ${#candidates} == 1 )); then\n"
        io << "    case \"$candidates[1]\" in\n"
        io << "      " << Directive::FILES << ") _files; return ;;\n"
        io << "      " << Directive::DIRS << ") _files -/; return ;;\n"
        # COMMAND directive: the candidate is the sentinel plus tab-separated
        # words of the embedded command. Rebuild `words`/`CURRENT` as that
        # command line and hand off to `_normal`, which dispatches to the
        # embedded command's own completion (or file completion by default).
        io << "      " << Directive::COMMAND << "*)\n"
        io << "        local tab=$'\\t'\n"
        io << "        local -a sub\n"
        io << "        sub=( \"${(@ps:$tab:)candidates[1]}\" )\n"
        io << "        shift sub\n"
        io << "        words=( \"${sub[@]}\" \"$PREFIX\" )\n"
        io << "        CURRENT=$#words\n"
        io << "        _normal\n"
        io << "        return ;;\n"
        io << "    esac\n"
        io << "  fi\n"
        io << "  compadd -- $candidates\n"
        io << "}\n"
        io << "compdef " << fn << ' ' << cmd << '\n'
      end
      script
    end
  end
end
