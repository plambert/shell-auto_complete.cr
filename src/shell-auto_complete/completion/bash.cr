module Shell::AutoComplete::Completion
  module Bash
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
      files = Directive::FILES
      dirs = Directive::DIRS
      "#{fn}() {\n" \
      "  local out cur\n" \
      "  cur=\"${COMP_WORDS[COMP_CWORD]}\"\n" \
      "  out=$(#{cmd} __complete \"$COMP_CWORD\" \"${COMP_WORDS[@]}\" 2>/dev/null)\n" \
      "  case \"$out\" in\n" \
      "    #{files})\n" \
      "      COMPREPLY=( $(compgen -f -- \"$cur\") )\n" \
      "      compopt -o filenames 2>/dev/null\n" \
      "      return\n" \
      "      ;;\n" \
      "    #{dirs})\n" \
      "      COMPREPLY=( $(compgen -d -- \"$cur\") )\n" \
      "      compopt -o filenames 2>/dev/null\n" \
      "      return\n" \
      "      ;;\n" \
      "  esac\n" \
      "  COMPREPLY=( $(compgen -W \"$out\" -- \"$cur\") )\n" \
      "}\n" \
      "complete -F #{fn} #{cmd}\n"
    end
  end
end
