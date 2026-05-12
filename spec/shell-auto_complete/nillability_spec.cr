require "../spec_helper"

Shell::AutoComplete.command NilIntCli, name: "ni", description: "x" do
  flag count : Int32?, "--count", "c"
end

Shell::AutoComplete.command NilStrCli, name: "ns", description: "x" do
  flag message : String?, "--message", "m"
end

describe "nillability via empty string" do
  it "sets a nullable Int32 to nil when given empty string" do
    NilIntCli.parse(["--count="]).count.should be_nil
  end

  it "leaves String? as empty string (special case)" do
    NilStrCli.parse(["--message="]).message.should eq("")
  end
end
