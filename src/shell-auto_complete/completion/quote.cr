module Shell::AutoComplete::Completion
  # Shell-quoting for values embedded in a generated completion script. The
  # command name (from `name:` or `File.basename(PROGRAM_NAME)`) and an absolute
  # executable path are arbitrary strings, so wherever they land in shell code
  # they must be quoted — otherwise a value with a space, a redirection like
  # `>`, or another metacharacter breaks the script or injects into the `eval`.
  module Quote
    # POSIX/bash/zsh single-quoting: wrap in single quotes and end/reopen the
    # quote around each embedded single quote (`'\''`).
    def self.posix(value : String) : String
      "'" + value.gsub("'") { "'\\''" } + "'"
    end

    # Fish single-quoting: inside single quotes fish honors only `\\` and `\'`,
    # so escape backslashes first, then single quotes.
    def self.fish(value : String) : String
      "'" + value.gsub("\\") { "\\\\" }.gsub("'") { "\\'" } + "'"
    end
  end
end
