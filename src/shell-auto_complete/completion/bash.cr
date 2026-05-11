module Shell::AutoComplete::Completion
  module Bash
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
      "#{fn}() {\n" \
      "  local out\n" \
      "  out=$(#{cmd} __complete \"$COMP_CWORD\" \"${COMP_WORDS[@]}\" 2>/dev/null)\n" \
      "  COMPREPLY=( $(compgen -W \"$out\" -- \"${COMP_WORDS[COMP_CWORD]}\") )\n" \
      "}\n" \
      "complete -F #{fn} #{cmd}\n"
    end
  end
end
