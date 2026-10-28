module Shell::AutoComplete::Completion
  module Bash
    # *executable*, when given, is the command the callback invokes for
    # `__complete` (an absolute path, so completion runs a specific binary
    # regardless of `PATH`); the command name still registers the completion.
    # Defaults to the command name.
    def self.render(klass, executable : String? = nil) : String
      cmd = klass.command_name
      fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
      reg = Quote.posix(cmd)
      call = Quote.posix(executable || cmd)
      files = Directive::FILES
      dirs = Directive::DIRS
      command = Directive::COMMAND
      # Readline hands the current word over as typed, with its opening quote
      # and backslash escapes, and inserts a COMPREPLY entry verbatim. The
      # function therefore dequotes the word before the binary and the prefix
      # filter see it, and escapes each candidate on the way back. Readline
      # keeps an opening quote the user typed and closes it after a unique
      # match, so a candidate is escaped for that quote style and otherwise
      # with `printf %q`. The prefix filter is a plain `case`, because
      # `compgen -W` expands the word list and mangles an apostrophe or `$`.
      #
      # Candidates are read one-per-line with `while IFS= read -r`, which
      # preserves spaces and glob metacharacters. Works on bash 3.2+ (the
      # macOS system bash) through 5.
      #
      # The COMMAND directive carries the already-typed words of an embedded
      # command as tab-separated payload; the handler rebuilds that command line
      # and delegates to bash-completion's `_command_offset` (command names for
      # the first word, the command's own completion after), falling back to
      # command/filename completion when bash-completion is not loaded.
      <<-BASH
        #{fn}() {
          local out raw cur line payload quote="" rest c sq="'\\\\''"
          raw="${COMP_WORDS[COMP_CWORD]}"
          cur="$raw"
          case "$cur" in
            \\"*) quote='"'; cur="${cur#\\"}" ;;
            \\'*) quote="'"; cur="${cur#\\'}" ;;
          esac
          if [ "$quote" != "'" ]; then
            rest="$cur"; cur=""
            while [ -n "$rest" ]; do
              c="${rest:0:1}"; rest="${rest:1}"
              if [ "$c" = '\\' ] && [ -n "$rest" ]; then
                case "${rest:0:1}" in
                  '"'|'\\'|'$'|'`') c="${rest:0:1}"; rest="${rest:1}" ;;
                  *) [ -z "$quote" ] && { c="${rest:0:1}"; rest="${rest:1}"; } ;;
                esac
              fi
              cur="$cur$c"
            done
          fi
          local -a words=( "${COMP_WORDS[@]}" )
          words[COMP_CWORD]="$cur"
          out=$(#{call} __complete "$COMP_CWORD" "${words[@]}" 2>/dev/null)
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
              COMP_WORDS=( "${sub[@]}" "$raw" )
              COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
              COMP_LINE="${COMP_WORDS[*]}"
              COMP_POINT=${#COMP_LINE}
              if declare -F _command_offset >/dev/null 2>&1; then
                _command_offset 0
              elif [ ${#sub[@]} -eq 0 ]; then
                while IFS= read -r line; do COMPREPLY+=( "$line" ); done < <(compgen -c -- "$raw")
              else
                while IFS= read -r line; do COMPREPLY+=( "$line" ); done < <(compgen -f -- "$raw")
                compopt -o filenames 2>/dev/null
              fi
              return
              ;;
          esac
          while IFS= read -r line; do
            [ -n "$line" ] || continue
            case "$line" in "$cur"*) ;; *) continue ;; esac
            case "$quote" in
              '"') line="${line//\\\\/\\\\\\\\}"; line="${line//\\"/\\\\\\"}"; line="${line//\\$/\\\\\\$}"; line="${line//\\`/\\\\\\`}" ;;
              "'") line="${line//\\'/$sq}" ;;
              *)   line=$(printf '%q' "$line") ;;
            esac
            COMPREPLY+=( "$line" )
          done <<< "$out"
        }
        complete -F #{fn} #{reg}\n
        BASH
    end
  end
end
