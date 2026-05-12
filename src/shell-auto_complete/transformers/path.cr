struct Path
  def self.__arg_transform(value : String, **opts) : Path
    Path.new(value)
  end
end

class File
  def self.__arg_transform(value : String, **opts) : Path
    raise ArgumentError.new("file does not exist: #{value}") unless File.exists?(value)
    raise ArgumentError.new("not a regular file: #{value}") unless File.file?(value)
    Path.new(value)
  end
end

class Dir
  def self.__arg_transform(value : String, **opts) : Path
    raise ArgumentError.new("directory does not exist: #{value}") unless Dir.exists?(value)
    Path.new(value)
  end
end
