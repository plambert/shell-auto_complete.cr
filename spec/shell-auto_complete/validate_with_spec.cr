require "../spec_helper"

Shell::AutoComplete.command VWCli, name: "v", description: "x" do
  flag count : Int32 = 1, "--count", "c", validate_with: :check_count

  def self.check_count(value : Int32) : Bool | String
    value.odd? ? true : "#{value} must be odd"
  end
end

Shell::AutoComplete.command VWFalseCli, name: "vf", description: "x" do
  flag count : Int32 = 1, "--count", "c", validate_with: :check_count_false

  def self.check_count_false(value : Int32) : Bool | String
    false # always rejects, generic message
  end
end

describe "validate_with:" do
  it "accepts a valid value" do
    VWCli.parse(["--count", "3"]).count.should eq(3)
  end

  it "raises with the custom string message" do
    expect_raises(Shell::AutoComplete::ParseError, /must be odd/) do
      VWCli.parse(["--count", "2"])
    end
  end

  it "raises generic message when validator returns false" do
    expect_raises(Shell::AutoComplete::ParseError, /not a valid count/) do
      VWFalseCli.parse(["--count", "5"])
    end
  end
end
