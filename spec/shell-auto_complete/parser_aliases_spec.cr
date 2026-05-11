require "../spec_helper"

Shell::AutoComplete.command AliasCli, name: "alias", description: "x" do
  flag message : String?, %w[--message --msg], "m"
end

describe "alias parsing" do
  it "accepts the canonical form" do
    AliasCli.parse(["--message", "hi"]).message.should eq("hi")
  end

  it "accepts an alias" do
    AliasCli.parse(["--msg", "hi"]).message.should eq("hi")
  end

  it "accepts the alias with =value syntax" do
    AliasCli.parse(["--msg=hi"]).message.should eq("hi")
  end
end
