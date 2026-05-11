require "../spec_helper"

Shell::AutoComplete.command SetCli, name: "se", description: "x" do
  flag tags : Set(String) = Set(String).new, "--tag", "t"
end

Shell::AutoComplete.command SetOpsCli, name: "so", description: "x" do
  flag levels : Set(String) = Set(String).new, "--level", "l", set_operations: true
end

describe "Set(T) flag" do
  it "starts empty when flag absent" do
    SetCli.parse([] of String).tags.should eq(Set(String).new)
  end

  it "deduplicates across multiple occurrences" do
    SetCli.parse(["--tag", "a", "--tag", "a", "--tag", "b"]).tags.should eq(Set{"a", "b"})
  end

  it "set_operations: + adds" do
    SetOpsCli.parse(["--level", "+debug", "--level", "+info"]).levels.should eq(Set{"debug", "info"})
  end

  it "set_operations: - removes" do
    SetOpsCli.parse(["--level", "+debug", "--level", "+info", "--level", "-debug"]).levels.should eq(Set{"info"})
  end

  it "set_operations: no prefix defaults to add" do
    SetOpsCli.parse(["--level", "debug"]).levels.should eq(Set{"debug"})
  end
end
