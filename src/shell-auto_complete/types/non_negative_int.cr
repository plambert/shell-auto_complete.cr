module Shell::AutoComplete::Types
  module NonNegativeInt
    def self.__arg_transform(value : String, **opts) : Int32
      value.to_i32
    end

    def self.__arg_validate(value : Int32, **opts) : Bool | String
      value >= 0 || "#{value} must be non-negative"
    end
  end
end
