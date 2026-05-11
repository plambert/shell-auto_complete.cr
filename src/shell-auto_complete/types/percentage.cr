module Shell::AutoComplete::Types
  module Percentage
    def self.__arg_transform(value : String, **opts) : Float64
      value.to_f64
    end

    def self.__arg_validate(value : Float64, **opts) : Bool | String
      (0.0..100.0).includes?(value) || "#{value} must be between 0.0 and 100.0"
    end
  end
end
