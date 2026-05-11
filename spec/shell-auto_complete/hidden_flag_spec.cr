require "../spec_helper"

Shell::AutoComplete.command HiddenCli, name: "h", description: "x" do
  flag debug : Bool = false, "--debug", "developer-only", hidden: true
  flag normal : String?, "--normal", "shown flag"
end

describe "hidden: true" do
  it "is parsed normally" do
    HiddenCli.parse(["--debug"]).debug.should be_true
  end

  it "is omitted from help" do
    HiddenCli.help.should_not contain("--debug")
    HiddenCli.help.should_not contain("developer-only")
  end

  it "leaves non-hidden flags visible" do
    HiddenCli.help.should contain("--normal")
    HiddenCli.help.should contain("shown flag")
  end
end
