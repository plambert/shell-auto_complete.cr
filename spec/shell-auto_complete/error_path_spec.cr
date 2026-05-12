require "../spec_helper"

Shell::AutoComplete.command ErrPathLeaf, name: "leaf", description: "x" do
  flag value : Int32?, "--value", "v"

  def run
  end
end

Shell::AutoComplete.command ErrPathMiddle, name: "middle", description: "x" do
  subcommand ErrPathLeaf
end

Shell::AutoComplete.command ErrPathRoot, name: "root", description: "x" do
  subcommand ErrPathMiddle
end

Shell::AutoComplete.command ErrPathNum, name: "num", description: "x" do
  flag count : Int32?, "--count", "c"

  def run
  end
end

describe "ParseError command_path" do
  it "sets command_path on leaf-level errors" do
    begin
      ErrPathLeaf.dispatch(["--bogus"], rescue_errors: false)
      fail "expected ParseError"
    rescue ex : Shell::AutoComplete::ParseError
      ex.command_path.should eq("leaf")
    end
  end

  it "builds the full path when error originates in a leaf reached via subcommands" do
    begin
      ErrPathRoot.dispatch(["middle", "leaf", "--bogus"], rescue_errors: false)
      fail "expected ParseError"
    rescue ex : Shell::AutoComplete::ParseError
      ex.command_path.should eq("root middle leaf")
    end
  end

  it "sets command_path to the parent name when error is 'unknown subcommand'" do
    begin
      ErrPathRoot.dispatch(["bogus"], rescue_errors: false)
      fail "expected ParseError"
    rescue ex : Shell::AutoComplete::ParseError
      ex.command_path.should eq("root")
    end
  end

  it "wraps ArgumentError as ParseError with command_path" do
    begin
      ErrPathNum.dispatch(["--count", "not-a-number"], rescue_errors: false)
      fail "expected ParseError"
    rescue ex : Shell::AutoComplete::ParseError
      ex.command_path.should eq("num")
    end
  end
end
