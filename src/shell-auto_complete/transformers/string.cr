class String
  def self.__arg_transform(value : String, **opts) : String
    value
  end

  def self.__arg_validate(value : String, **opts) : Bool | String
    if re = opts[:matches]?
      return "#{value} does not match #{re}" unless re.matches?(value)
    end
    if choices = opts[:choices]?
      return "#{value} is not one of #{choices.join(", ")}" unless choices.includes?(value)
    end
    true
  end
end
