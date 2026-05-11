require "../spec_helper"

Shell::AutoComplete.command HashCli, name: "h", description: "x" do
  flag env : Hash(String, String) = {} of String => String, "--env", "e"
end

describe "Hash(String, T) flag" do
  it "parses key=value" do
    inst = HashCli.parse(["--env", "FOO=bar"])
    inst.env.should eq({"FOO" => "bar"})
  end

  it "accumulates multiple --env occurrences" do
    inst = HashCli.parse(["--env", "FOO=bar", "--env", "BAZ=qux"])
    inst.env.should eq({"FOO" => "bar", "BAZ" => "qux"})
  end

  it "deletes with -key" do
    inst = HashCli.parse(["--env", "FOO=bar", "--env", "-FOO"])
    inst.env.should eq({} of String => String)
  end
end
