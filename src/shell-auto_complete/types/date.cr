module Shell::AutoComplete::Types
  module Date
    def self.__arg_transform(value : String, **opts) : Time
      Time.parse(value, "%Y-%m-%d", Time::Location::UTC)
    end

    def self.__arg_validate(value : Time, **opts) : Bool | String
      true
    end
  end
end
