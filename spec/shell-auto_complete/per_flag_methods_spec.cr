require "../spec_helper"

# Per-flag transformer
Shell::AutoComplete.command PFTransformCli, name: "pft", description: "x" do
  flag count : Int32?, "--count", "c"

  def self.__arg_transform_count(value : String) : Int32
    value.to_i * 100
  end
end

# Per-flag validator
Shell::AutoComplete.command PFValidateCli, name: "pfv", description: "x" do
  flag count : Int32 = 1, "--count", "c"

  def self.__arg_validate_count(value : Int32, **opts) : Bool | String
    value.even? ? true : "#{value} must be even"
  end
end

describe "per-flag __arg_transform_<name>" do
  it "uses the method instead of type's __arg_transform" do
    PFTransformCli.parse(["--count", "3"]).count.should eq(300)
  end
end

describe "per-flag __arg_validate_<name>" do
  it "accepts a valid value" do
    PFValidateCli.parse(["--count", "4"]).count.should eq(4)
  end

  it "rejects an invalid value" do
    expect_raises(Shell::AutoComplete::ParseError, /must be even/) do
      PFValidateCli.parse(["--count", "3"])
    end
  end
end
