module Shell::AutoComplete::Types
  module EnvVar
    NAME_RE = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    def self.__arg_transform(value : String, **opts) : String
      value
    end

    def self.__arg_validate(value : String, **opts) : Bool | String
      NAME_RE.matches?(value) || "#{value} is not a valid environment variable name"
    end

    # Complete against the names of the variables set in the current
    # environment (the completion helper runs in the user's shell, so this is
    # the environment the value will be resolved against).
    def self.__arg_complete(prefix : String, **opts) : Array(String)
      ENV.keys.select(&.starts_with?(prefix)).sort!
    end
  end
end
