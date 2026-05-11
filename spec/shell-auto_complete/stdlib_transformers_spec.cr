require "../spec_helper"
require "uri"
require "log"
require "socket"

Shell::AutoComplete.command UriCli, name: "u", description: "x" do
  flag site : URI?, "--site", "s"
end

Shell::AutoComplete.command TimeCli, name: "t", description: "x" do
  flag at : Time?, "--at", "a"
end

Shell::AutoComplete.command LogSevCli, name: "ls", description: "x" do
  flag level : Log::Severity?, "--level", "l"
end

Shell::AutoComplete.command RegexCli, name: "r", description: "x" do
  flag pattern : Regex?, "--pattern", "p"
end

describe "stdlib transformers" do
  it "parses URI" do
    UriCli.parse(["--site", "https://example.com"]).site.should eq(URI.parse("https://example.com"))
  end

  it "parses Time in ISO 8601" do
    inst = TimeCli.parse(["--at", "2026-05-10T12:00:00Z"])
    inst.at.should_not be_nil
  end

  it "parses Log::Severity" do
    LogSevCli.parse(["--level", "warn"]).level.should eq(Log::Severity::Warn)
  end

  it "parses Regex" do
    inst = RegexCli.parse(["--pattern", "foo.*bar"])
    inst.pattern.try(&.matches?("fooXbar")).should be_true
  end
end
