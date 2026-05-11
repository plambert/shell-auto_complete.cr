require "../spec_helper"

Shell::AutoComplete.command ShortCli, name: "short", description: "x" do
  flag message : String?, "--message", "-m", "m"
end

describe "short flag parsing" do
  it "accepts -m value (separate token)" do
    ShortCli.parse(["-m", "hi"]).message.should eq("hi")
  end

  it "rejects -mvalue (no inline short value support)" do
    expect_raises(Shell::AutoComplete::ParseError) do
      ShortCli.parse(["-mhi"])
    end
  end

  it "rejects unknown short flag" do
    expect_raises(Shell::AutoComplete::ParseError) do
      ShortCli.parse(["-x"])
    end
  end
end
