require "../spec_helper"

# Issue #49: scalar flag validation errors must name the flag, using the same
# "--flag: message" shape the collection paths already produce.

Shell::AutoComplete.command ScalarNameRangeCli, name: "snr", description: "x" do
  flag port : Int32 = 8080, "--port", "-p", "p", range: 1..65535
end

Shell::AutoComplete.command ScalarNameChoicesCli, name: "snc", description: "x" do
  flag color : String?, "--color", "c", choices: %w[red green blue]
end

Shell::AutoComplete.command ScalarNameMatchesCli, name: "snm", description: "x" do
  flag name : String?, "--name", "n", matches: /\A[a-z]+\z/
end

Shell::AutoComplete.command ScalarNameVWCli, name: "snv", description: "x" do
  flag count : Int32 = 1, "--count", "c", validate_with: :check_odd
  flag level : Int32 = 1, "--level", "l", validate_with: :always_false

  def self.check_odd(value : Int32) : Bool | String
    value.odd? ? true : "#{value} must be odd"
  end

  def self.always_false(value : Int32) : Bool | String
    false
  end
end

Shell::AutoComplete.command ScalarNamePerFlagCli, name: "snp", description: "x" do
  flag size : Int32 = 1, "--size", "s"

  def self.__arg_transform_size(value : String) : Int32
    raise ArgumentError.new("bad size #{value}") if value == "bad"
    value.to_i
  end

  def self.__arg_validate_size(value : Int32) : Bool | String
    value > 0 ? true : "#{value} is not positive"
  end
end

Shell::AutoComplete.command ScalarNameTWCli, name: "snt", description: "x" do
  flag scale : Int32 = 1, "--scale", "s", transform_with: :parse_scale

  def self.parse_scale(value : String) : Int32
    raise ArgumentError.new("unusable scale #{value}") if value == "nope"
    value.to_i
  end
end

Shell::AutoComplete.command ScalarNameControlCli, name: "snk", description: "x" do
  flag ports : Array(Int32) = [] of Int32, "--ports", "p", delimiter: ",", range: 1..65535
end

private def flag_error(regex : Regex, flag : String, &)
  error = expect_raises(Shell::AutoComplete::ParseError, regex) do
    yield
  end
  (error.message || "").scan(flag).size.should eq(1)
end

describe "scalar flag errors name the flag (issue #49)" do
  it "prefixes range: failures with the canonical flag" do
    flag_error(/\A--port: 70000 out of range 1\.\.65535\z/, "--port") do
      ScalarNameRangeCli.parse(["--port", "70000"])
    end
  end

  it "prefixes choices: failures with the canonical flag" do
    flag_error(/\A--color: purple is not one of red, green, blue\z/, "--color") do
      ScalarNameChoicesCli.parse(["--color", "purple"])
    end
  end

  it "prefixes matches: failures with the canonical flag" do
    flag_error(/\A--name: ABC does not match/, "--name") do
      ScalarNameMatchesCli.parse(["--name", "ABC"])
    end
  end

  it "prefixes validate_with: string messages with the canonical flag" do
    flag_error(/\A--count: 2 must be odd\z/, "--count") do
      ScalarNameVWCli.parse(["--count", "2"])
    end
  end

  it "prefixes the generic false-validator message with the canonical flag" do
    flag_error(/\A--level: not a valid level\z/, "--level") do
      ScalarNameVWCli.parse(["--level", "3"])
    end
  end

  it "prefixes stock type transform failures with the canonical flag" do
    flag_error(/\A--port: /, "--port") do
      ScalarNameRangeCli.parse(["--port", "abc"])
    end
  end

  it "prefixes __arg_transform_<name> ArgumentError with the canonical flag" do
    flag_error(/\A--size: bad size bad\z/, "--size") do
      ScalarNamePerFlagCli.parse(["--size", "bad"])
    end
  end

  it "prefixes __arg_validate_<name> string messages with the canonical flag" do
    flag_error(/\A--size: 0 is not positive\z/, "--size") do
      ScalarNamePerFlagCli.parse(["--size", "0"])
    end
  end

  it "prefixes transform_with: ArgumentError with the canonical flag" do
    flag_error(/\A--scale: unusable scale nope\z/, "--scale") do
      ScalarNameTWCli.parse(["--scale", "nope"])
    end
  end

  it "prefixes the canonical spelling even when an alias is typed" do
    flag_error(/\A--port: 0 out of range 1\.\.65535\z/, "--port") do
      ScalarNameRangeCli.parse(["-p", "0"])
    end
  end

  it "leaves the collection flag format unchanged (control)" do
    flag_error(/\A--ports: 0 out of range 1\.\.65535\z/, "--ports") do
      ScalarNameControlCli.parse(["--ports", "80,0"])
    end
  end
end
