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

    # All known directive sentinels.
    def self.all : Array(String)
      [FILES, DIRS]
    end

    # Whether *line* is a directive sentinel.
    def self.directive?(line : String) : Bool
      line == FILES || line == DIRS
    end
  end
end
