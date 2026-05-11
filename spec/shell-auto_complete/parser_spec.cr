require "../spec_helper"

Shell::AutoComplete.command ParseCli, name: "parse", description: "x" do
  flag message : String?, "--message", "the message"
end

describe "ParseCli.parse" do
  it "parses --message value (separate token)" do
    inst = ParseCli.parse(["--message", "hello"])
    inst.message.should eq("hello")
  end

  it "parses --message=value (inline)" do
    inst = ParseCli.parse(["--message=hello"])
    inst.message.should eq("hello")
  end

  it "leaves the flag nil when absent" do
    inst = ParseCli.parse([] of String)
    inst.message.should be_nil
  end

  it "raises ParseError for unknown flags" do
    expect_raises(Shell::AutoComplete::ParseError) do
      ParseCli.parse(["--bogus"])
    end
  end

  it "raises ParseError when a value-taking flag is missing its value" do
    expect_raises(Shell::AutoComplete::ParseError) do
      ParseCli.parse(["--message"])
    end
  end

  it "rejects non-flag tokens when no positional is declared" do
    # Phase 10: commands with no positional declarations reject bare tokens.
    expect_raises(Shell::AutoComplete::ParseError, /too many/) do
      ParseCli.parse(["alpha", "--message", "x"])
    end
  end
end
