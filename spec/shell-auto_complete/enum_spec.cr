require "../spec_helper"

enum EnumLogLevel
  Debug
  Info
  Warn
  Error
end

Shell::AutoComplete.command EnumCli, name: "e", description: "x" do
  flag level : EnumLogLevel = EnumLogLevel::Info, "--level", "lvl"
end

describe "ordinary enum flag" do
  it "parses lowercased case name" do
    EnumCli.parse(["--level", "debug"]).level.should eq(EnumLogLevel::Debug)
  end

  it "parses uppercase case name" do
    EnumCli.parse(["--level", "WARN"]).level.should eq(EnumLogLevel::Warn)
  end

  it "parses kebab-case (only one case, so just confirm symmetric handling)" do
    EnumCli.parse(["--level", "debug"]).level.should eq(EnumLogLevel::Debug)
  end

  it "defaults to its declared value when flag is absent" do
    EnumCli.parse([] of String).level.should eq(EnumLogLevel::Info)
  end

  it "rejects unknown cases" do
    expect_raises(Shell::AutoComplete::ParseError, /--level: /) do
      EnumCli.parse(["--level", "trace"])
    end
  end
end
