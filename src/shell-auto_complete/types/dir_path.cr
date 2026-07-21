module Shell::AutoComplete::Types
  # A directory-shaped value that need not exist on the local filesystem.
  # Completes as a directory, like `Dir`, but performs no existence check,
  # like `Path`.
  #
  # The stock path types cover three of the four useful combinations of
  # "completes files or directories" and "must already exist": `Path`
  # completes files and directories without checking, `File` and `Dir` check.
  # This fills the fourth — a value that names a directory somewhere the
  # local filesystem cannot vouch for:
  #
  # * a directory on another host (a path handed to a daemon or a remote API)
  # * a directory the program creates later (`Dir.mkdir_p` on first run)
  #
  # `Dir` rejects both at parse time; `Path` accepts them but offers files
  # alongside directories when completing. Values are stored as `::Path`,
  # exactly as `Path`, `File`, and `Dir` flags are.
  module DirPath
    def self.__arg_transform(value : String, **opts) : ::Path
      ::Path.new(value)
    end

    # Delegate to the shell's native directory-only completion.
    def self.__arg_complete(prefix : String, **opts) : Array(String)
      [::Shell::AutoComplete::Completion::Directive::DIRS]
    end
  end
end
