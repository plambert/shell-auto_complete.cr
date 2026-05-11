require "../spec_helper"

enum SCFLevel
  Debug
  Info
  Warn
  Error
end

Shell::AutoComplete.command SCFCli, name: "s", description: "x" do
  flag level : SCFLevel = SCFLevel::Info, "--level", "l", shortcut_flags: true
end

describe "shortcut_flags: true" do
  it "still parses canonical form" do
    SCFCli.parse(["--level", "debug"]).level.should eq(SCFLevel::Debug)
  end

  it "generates --debug shortcut" do
    SCFCli.parse(["--debug"]).level.should eq(SCFLevel::Debug)
  end

  it "generates --warn shortcut" do
    SCFCli.parse(["--warn"]).level.should eq(SCFLevel::Warn)
  end

  it "applies last-one-wins on conflict" do
    SCFCli.parse(["--debug", "--error"]).level.should eq(SCFLevel::Error)
  end
end
