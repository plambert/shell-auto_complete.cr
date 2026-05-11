struct Int8
  def self.__arg_transform(value : String, **opts) : Int8
    value.to_i8
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct Int16
  def self.__arg_transform(value : String, **opts) : Int16
    value.to_i16
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct Int32
  def self.__arg_transform(value : String, **opts) : Int32
    value.to_i32
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct Int64
  def self.__arg_transform(value : String, **opts) : Int64
    value.to_i64
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct UInt8
  def self.__arg_transform(value : String, **opts) : UInt8
    value.to_u8
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct UInt16
  def self.__arg_transform(value : String, **opts) : UInt16
    value.to_u16
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct UInt32
  def self.__arg_transform(value : String, **opts) : UInt32
    value.to_u32
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct UInt64
  def self.__arg_transform(value : String, **opts) : UInt64
    value.to_u64
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct Float32
  def self.__arg_transform(value : String, **opts) : Float32
    value.to_f32
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end

struct Float64
  def self.__arg_transform(value : String, **opts) : Float64
    value.to_f64
  end

  def self.__arg_validate(value : self, **opts) : Bool | String
    if range = opts[:range]?
      return "#{value} out of range #{range}" unless range.includes?(value)
    end
    true
  end
end
