module Shell::AutoComplete::Types
  module EnvVar
    NAME_RE = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    def self.__arg_transform(value : String, **opts) : String
      value
    end

    def self.__arg_validate(value : String, **opts) : Bool | String
      NAME_RE.matches?(value) || "#{value} is not a valid environment variable name"
    end
  end
end
