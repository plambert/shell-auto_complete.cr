require "../spec_helper"

describe "Shell::AutoComplete::Types::PositiveInt" do
  it "transforms valid string" do
    Shell::AutoComplete::Types::PositiveInt.__arg_transform("5").should eq(5)
  end

  it "accepts positive values" do
    Shell::AutoComplete::Types::PositiveInt.__arg_validate(5).should be_true
  end

  it "rejects zero and negative" do
    Shell::AutoComplete::Types::PositiveInt.__arg_validate(0).should be_a(String)
    Shell::AutoComplete::Types::PositiveInt.__arg_validate(-1).should be_a(String)
  end
end

describe "Shell::AutoComplete::Types::NonNegativeInt" do
  it "accepts zero" do
    Shell::AutoComplete::Types::NonNegativeInt.__arg_validate(0).should be_true
  end

  it "rejects negative" do
    Shell::AutoComplete::Types::NonNegativeInt.__arg_validate(-1).should be_a(String)
  end
end

describe "Shell::AutoComplete::Types::Percentage" do
  it "transforms and validates 50.0" do
    v = Shell::AutoComplete::Types::Percentage.__arg_transform("50.0")
    v.should eq(50.0)
    Shell::AutoComplete::Types::Percentage.__arg_validate(v).should be_true
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
    Shell::AutoComplete::Types::EnvVar.__arg_validate("PATH").should be_true
    Shell::AutoComplete::Types::EnvVar.__arg_validate("_FOO").should be_true
    Shell::AutoComplete::Types::EnvVar.__arg_validate("a1b2").should be_true
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

# Regression: a synthetic type's storage differs from its declared type
# (PositiveInt is stored as Int32), and the scalar-flag validate dispatch read
# the storage type — which carries no __arg_validate — so the validator was
# silently skipped. Positionals always resolved this correctly.
Shell::AutoComplete.command SynthFlags, name: "synth", description: "x" do
  flag amount : Shell::AutoComplete::Types::PositiveInt?, "--amount", "positive"
  flag tries : Shell::AutoComplete::Types::PositiveInt = 10, "--tries", "positive, defaulted"
  flag name : Shell::AutoComplete::Types::EnvVar?, "--name", "env var"
  flag pct : Shell::AutoComplete::Types::Percentage?, "--pct", "percent"

  def run
  end
end

Shell::AutoComplete.command SynthPos, name: "synthpos", description: "x" do
  positional count : Shell::AutoComplete::Types::PositiveInt, "positive"

  def run
  end
end

describe "synthetic types as flag declarations" do
  it "runs PositiveInt's validator on a nilable flag" do
    expect_raises(Shell::AutoComplete::ParseError, /--amount: 0 must be positive/) do
      SynthFlags.parse(["--amount", "0"])
    end
  end

  it "runs the validator on a flag that declares a default" do
    expect_raises(Shell::AutoComplete::ParseError, /--tries: 0 must be positive/) do
      SynthFlags.parse(["--tries", "0"])
    end
  end

  it "keeps a declared default on a storage-remapped flag" do
    SynthFlags.parse([] of String).tries.should eq(10)
  end

  it "runs EnvVar's validator" do
    expect_raises(Shell::AutoComplete::ParseError, /--name: 1nope is not a valid/) do
      SynthFlags.parse(["--name", "1nope"])
    end
  end

  it "runs Percentage's validator" do
    expect_raises(Shell::AutoComplete::ParseError, /--pct: 150.0 must be between/) do
      SynthFlags.parse(["--pct", "150"])
    end
  end

  it "accepts valid values across all of them" do
    inst = SynthFlags.parse(["--amount", "3", "--tries", "4", "--name", "HOME", "--pct", "50"])
    inst.amount.should eq(3)
    inst.tries.should eq(4)
    inst.name.should eq("HOME")
    inst.pct.should eq(50.0)
  end

  it "still validates a synthetic-typed positional" do
    expect_raises(Shell::AutoComplete::ParseError, /count: 0 must be positive/) do
      SynthPos.parse(["0"])
    end
  end
end
