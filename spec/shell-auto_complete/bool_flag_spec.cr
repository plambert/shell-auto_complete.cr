require "../spec_helper"

Shell::AutoComplete.command BoolCli, name: "bool", description: "x" do
  flag color : Bool = true, "--color", "colorize"
end

Shell::AutoComplete.command BoolFalseCli, name: "boolf", description: "x" do
  flag verbose : Bool = false, "--verbose", "-V", "verbose"
end

describe "Bool flag" do
  it "defaults to its declared value (true)" do
    BoolCli.parse([] of String).color.should be_true
  end

  it "defaults to its declared value (false)" do
    BoolFalseCli.parse([] of String).verbose.should be_false
  end

  it "accepts --color" do
    BoolCli.parse(["--color"]).color.should be_true
  end

  it "accepts --no-color" do
    BoolCli.parse(["--no-color"]).color.should be_false
  end

  it "accepts short flag for Bool" do
    BoolFalseCli.parse(["-V"]).verbose.should be_true
  end

  it "does NOT auto-generate -No-V (short flag has no negation)" do
    expect_raises(Shell::AutoComplete::ParseError) do
      BoolFalseCli.parse(["-No-V"])
    end
  end

  it "last-occurrence wins (e.g., --color --no-color → false)" do
    BoolCli.parse(["--color", "--no-color"]).color.should be_false
  end
end
