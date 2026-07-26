module Shell::AutoComplete::Completion
  # Sentinel lines emitted by `__complete` to ask the generated shell wrapper to
  # perform *native* filesystem completion instead of word-list completion.
  #
  # A path-typed argument can't be completed well from Crystal: the shell already
  # knows how to expand `~`, color entries, append trailing slashes for
  # directories, and respect `-o filenames`. Rather than enumerate the filesystem
  # ourselves, a path completer emits one of these directives and the wrapper
  # turns it into the shell's own file/dir completion (`compgen -f`/`-d`,
  # `_files`, `__fish_complete_path`).
  module Directive
    # Complete against files *and* directories (`Path`, `File`).
    FILES = "__sac_complete_files__"
    # Complete against directories only (`Dir`).
    DIRS = "__sac_complete_dirs__"
    # Delegate to the shell's own command-line completion for an embedded
    # command (`delimited_flag ..., external_command: true`). The line is this
    # sentinel followed by tab-separated words already typed in the captured
    # command, so the wrapper completes `<those words> <current>` as a fresh
    # command line — command names for the first word, the command's own
    # completion for the rest, falling back to filenames.
    COMMAND = "__sac_complete_command__"

    # All known directive sentinels.
    def self.all : Array(String)
      [FILES, DIRS, COMMAND]
    end

    # Builds a COMMAND directive line carrying the already-typed words of the
    # captured command as its tab-separated payload.
    def self.command(words : Array(String)) : String
      ([COMMAND] + words).join('\t')
    end

    # Whether *line* is a directive sentinel (COMMAND matches with or without a
    # payload).
    def self.directive?(line : String) : Bool
      line == FILES || line == DIRS || line == COMMAND || line.starts_with?(COMMAND + "\t")
    end
  end
end
