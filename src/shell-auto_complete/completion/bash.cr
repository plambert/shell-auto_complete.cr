module Shell::AutoComplete::Completion
  module Bash
    def self.render(klass) : String
      cmd = klass.command_name
      fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
      files = Directive::FILES
      dirs = Directive::DIRS
      command = Directive::COMMAND
      # Candidates are read one-per-line into COMPREPLY with `while IFS= read -r`
      # rather than `COMPREPLY=( $(compgen ...) )`. The unquoted-substitution
      # form word-splits each candidate on $IFS and then glob-expands it; reading
      # line by line preserves spaces and glob metacharacters verbatim. Works on
      # bash 3.2+ (the macOS system bash) through 5.
      #
      # The COMMAND directive carries the already-typed words of an embedded
      # command as tab-separated payload; the handler rebuilds that command line
      # and delegates to bash-completion's `_command_offset` (command names for
      # the first word, the command's own completion after), falling back to
      # command/filename completion when bash-completion is not loaded.
      <<-BASH
        #{fn}() {
          local out cur line payload
          cur="${COMP_WORDS[COMP_CWORD]}"
          out=$(#{cmd} __complete "$COMP_CWORD" "${COMP_WORDS[@]}" 2>/dev/null)
          COMPREPLY=()
          case "$out" in
            #{files})
              while IFS= read -r line; do COMPREPLY+=( "$line" ); done < <(compgen -f -- "$cur")
              compopt -o filenames 2>/dev/null
              return
              ;;
            #{dirs})
              while IFS= read -r line; do COMPREPLY+=( "$line" ); done < <(compgen -d -- "$cur")
              compopt -o filenames 2>/dev/null
              return
              ;;
            #{command}*)
              payload="${out#'#{command}'}"
              payload="${payload#$'\\t'}"
              local -a sub=()
              if [ -n "$payload" ]; then
                local _oifs="$IFS"; IFS=$'\\t'; read -r -a sub <<< "$payload"; IFS="$_oifs"
              fi
              COMP_WORDS=( "${sub[@]}" "$cur" )
              COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
              COMP_LINE="${COMP_WORDS[*]}"
              COMP_POINT=${#COMP_LINE}
              if declare -F _command_offset >/dev/null 2>&1; then
                _command_offset 0
              elif [ ${#sub[@]} -eq 0 ]; then
                while IFS= read -r line; do COMPREPLY+=( "$line" ); done < <(compgen -c -- "$cur")
              else
                while IFS= read -r line; do COMPREPLY+=( "$line" ); done < <(compgen -f -- "$cur")
                compopt -o filenames 2>/dev/null
              fi
              return
              ;;
          esac
          while IFS= read -r line; do
            [ -n "$line" ] && COMPREPLY+=( "$line" )
          done < <(IFS=$'\\n'; compgen -W "$out" -- "$cur")
        }
        complete -F #{fn} #{cmd}\n
        BASH
    end
  end
end
