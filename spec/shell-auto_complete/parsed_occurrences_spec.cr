require "../spec_helper"
require "log"

# Issue #11: parsed_occurrences — a raw, ordered log of every flag occurrence.

Shell::AutoComplete.command OccurrenceCli, name: "occ", description: "x" do
  flag after : String?, "--after", "--since", "-a", "After"
  flag covers : Bool = false, "--covers", "Covers"
  flag level : Log::Severity?, "--level", "Level", shortcut_flags: true
  positionals names : Array(String), "Names"
end

describe "parsed_occurrences" do
  it "records flags in command-line order with spellings as typed" do
    inst = OccurrenceCli.parse(["--after", "1", "-a", "2", "--since=3", "--covers", "--no-covers"])
    inst.parsed_occurrences.should eq([
      {"--after", "1"},
      {"-a", "2"},
      {"--since", "3"},
      {"--covers", nil},
      {"--no-covers", nil},
    ])
    inst.after.should eq("3")
    inst.covers.should be_false
  end

  it "logs nil for forced-value shortcut flags" do
    inst = OccurrenceCli.parse(["--warn"])
    inst.parsed_occurrences.should eq([{"--warn", nil}])
    inst.level.should eq(Log::Severity::Warn)
  end

  it "does not log positionals or anything after --" do
    inst = OccurrenceCli.parse(["alpha", "--covers", "--", "--after"])
    inst.parsed_occurrences.should eq([{"--covers", nil}])
    inst.names.should eq(["alpha", "--after"])
  end

  it "is empty when no flags are given" do
    OccurrenceCli.parse(["alpha"]).parsed_occurrences.should be_empty
  end
end
