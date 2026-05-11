require "../spec_helper"

describe "Shell::AutoComplete::Types::PositiveInt" do
  it "transforms valid string" do
    Shell::AutoComplete::Types::PositiveInt.__arg_transform("5").should eq(5)
  end

  it "accepts positive values" do
    Shell::AutoComplete::Types::PositiveInt.__arg_validate(5).should eq(true)
  end

  it "rejects zero and negative" do
    Shell::AutoComplete::Types::PositiveInt.__arg_validate(0).should be_a(String)
    Shell::AutoComplete::Types::PositiveInt.__arg_validate(-1).should be_a(String)
  end
end

describe "Shell::AutoComplete::Types::NonNegativeInt" do
  it "accepts zero" do
    Shell::AutoComplete::Types::NonNegativeInt.__arg_validate(0).should eq(true)
  end

  it "rejects negative" do
    Shell::AutoComplete::Types::NonNegativeInt.__arg_validate(-1).should be_a(String)
  end
end

describe "Shell::AutoComplete::Types::Percentage" do
  it "transforms and validates 50.0" do
    v = Shell::AutoComplete::Types::Percentage.__arg_transform("50.0")
    v.should eq(50.0)
    Shell::AutoComplete::Types::Percentage.__arg_validate(v).should eq(true)
  end

  it "rejects above 100" do
    Shell::AutoComplete::Types::Percentage.__arg_validate(101.0).should be_a(String)
  end

  it "rejects negative" do
    Shell::AutoComplete::Types::Percentage.__arg_validate(-1.0).should be_a(String)
  end
end

describe "Shell::AutoComplete::Types::EpochTime" do
  it "parses float seconds" do
    t = Shell::AutoComplete::Types::EpochTime.__arg_transform("1700000000")
    t.should be_a(Time)
    t.to_unix.should eq(1700000000)
  end
end

describe "Shell::AutoComplete::Types::Date" do
  it "parses YYYY-MM-DD" do
    t = Shell::AutoComplete::Types::Date.__arg_transform("2026-05-10")
    t.should be_a(Time)
    t.year.should eq(2026)
    t.month.should eq(5)
    t.day.should eq(10)
  end
end

describe "Shell::AutoComplete::Types::EnvVar" do
  it "accepts valid env var names" do
    Shell::AutoComplete::Types::EnvVar.__arg_transform("PATH").should eq("PATH")
    Shell::AutoComplete::Types::EnvVar.__arg_validate("PATH").should eq(true)
    Shell::AutoComplete::Types::EnvVar.__arg_validate("_FOO").should eq(true)
    Shell::AutoComplete::Types::EnvVar.__arg_validate("a1b2").should eq(true)
  end

  it "rejects names with hyphens" do
    Shell::AutoComplete::Types::EnvVar.__arg_validate("PA-TH").should be_a(String)
  end

  it "rejects names starting with a digit" do
    Shell::AutoComplete::Types::EnvVar.__arg_validate("1PATH").should be_a(String)
  end
end

# End-to-end: wire PositiveInt via transform_with + validate_with
Shell::AutoComplete.command SynthCli, name: "synth", description: "x" do
  flag count : Int32?, "--count", "c",
    transform_with: :transform_count,
    validate_with: :validate_count

  def self.transform_count(value : String) : Int32
    Shell::AutoComplete::Types::PositiveInt.__arg_transform(value)
  end

  def self.validate_count(value : Int32)
    Shell::AutoComplete::Types::PositiveInt.__arg_validate(value)
  end
end

describe "synthetic type wiring via transform_with/validate_with" do
  it "accepts a positive value" do
    SynthCli.parse(["--count", "5"]).count.should eq(5)
  end

  it "rejects zero" do
    expect_raises(Shell::AutoComplete::ParseError) do
      SynthCli.parse(["--count", "0"])
    end
  end
end
