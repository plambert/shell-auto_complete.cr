module Shell::AutoComplete::Completion
  module Bash
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
      files = Directive::FILES
      dirs = Directive::DIRS
      # Candidates are read one-per-line into COMPREPLY with `while IFS= read -r`
      # rather than `COMPREPLY=( $(compgen ...) )`. The unquoted-substitution form
      # word-splits each candidate on $IFS (so a filename with spaces is torn into
      # several entries) and then glob-expands it; reading line by line preserves
      # spaces and other glob metacharacters verbatim. Works on bash 3.2+ (the
      # macOS system bash) through 5.
      "#{fn}() {\n" \
      "  local out cur line\n" \
      "  cur=\"${COMP_WORDS[COMP_CWORD]}\"\n" \
      "  out=$(#{cmd} __complete \"$COMP_CWORD\" \"${COMP_WORDS[@]}\" 2>/dev/null)\n" \
      "  COMPREPLY=()\n" \
      "  case \"$out\" in\n" \
      "    #{files})\n" \
      "      while IFS= read -r line; do COMPREPLY+=( \"$line\" ); done < <(compgen -f -- \"$cur\")\n" \
      "      compopt -o filenames 2>/dev/null\n" \
      "      return\n" \
      "      ;;\n" \
      "    #{dirs})\n" \
      "      while IFS= read -r line; do COMPREPLY+=( \"$line\" ); done < <(compgen -d -- \"$cur\")\n" \
      "      compopt -o filenames 2>/dev/null\n" \
      "      return\n" \
      "      ;;\n" \
      "  esac\n" \
      "  while IFS= read -r line; do\n" \
      "    [ -n \"$line\" ] && COMPREPLY+=( \"$line\" )\n" \
      "  done < <(IFS=$'\\n'; compgen -W \"$out\" -- \"$cur\")\n" \
      "}\n" \
      "complete -F #{fn} #{cmd}\n"
    end
  end
end
