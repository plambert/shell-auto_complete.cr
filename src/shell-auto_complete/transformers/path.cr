struct Path
  def self.__arg_transform(value : String, **opts) : Path
    Path.new(value)
  end
end
