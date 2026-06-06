# :nodoc:
struct Path
  def self.__arg_transform(value : String, **opts) : Path
    Path.new(value)
  end

  # Delegate to the shell's native file completion (files and directories).
  def self.__arg_complete(prefix : String, **opts) : Array(String)
    [::Shell::AutoComplete::Completion::Directive::FILES]
  end
end

# :nodoc:
class File
  def self.__arg_transform(value : String, **opts) : Path
    raise ArgumentError.new("file does not exist: #{value}") unless File.exists?(value)
    raise ArgumentError.new("not a regular file: #{value}") unless File.file?(value)
    Path.new(value)
  end

  # Delegate to the shell's native file completion (files and directories — the
  # shell needs directories visible so the user can descend toward a file).
  def self.__arg_complete(prefix : String, **opts) : Array(String)
    [::Shell::AutoComplete::Completion::Directive::FILES]
  end
end

# :nodoc:
class Dir
  def self.__arg_transform(value : String, **opts) : Path
    raise ArgumentError.new("directory does not exist: #{value}") unless Dir.exists?(value)
    Path.new(value)
  end

  # Delegate to the shell's native directory-only completion.
  def self.__arg_complete(prefix : String, **opts) : Array(String)
    [::Shell::AutoComplete::Completion::Directive::DIRS]
  end
end
