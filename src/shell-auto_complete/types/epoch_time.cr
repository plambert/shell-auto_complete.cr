module Shell::AutoComplete::Types
  module EpochTime
    def self.__arg_transform(value : String, **opts) : Time
      Time.unix(value.to_f.to_i64)
    end

    def self.__arg_validate(value : Time, **opts) : Bool | String
      true
    end
  end
end
