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

# Issue #20: widened key charset, hash_operations: opt-out, derived delete
# pattern, and targeted -key=value errors.

Shell::AutoComplete.command HashPolishCli, name: "hp", description: "x" do
  flag conf : Hash(String, String) = {} of String => String, "--conf", "Config entries"
  flag env : Hash(String, String) = {} of String => String, "--env", "Env entries",
    hash_operations: false
end

describe "hash flag key charset" do
  it "accepts dotted keys" do
    HashPolishCli.parse(["--conf", "a.b=1"]).conf.should eq({"a.b" => "1"})
  end

  it "accepts colon-namespaced keys" do
    HashPolishCli.parse(["--conf", "log:level=debug"]).conf.should eq({"log:level" => "debug"})
  end

  it "deletes dotted keys with the derived pattern" do
    inst = HashPolishCli.parse(["--conf", "a.b=1", "--conf", "-a.b"])
    inst.conf.should be_empty
  end
end

describe "hash_operations: false" do
  it "still assigns" do
    HashPolishCli.parse(["--env", "PATH=/bin"]).env.should eq({"PATH" => "/bin"})
  end

  it "rejects the bare -key delete form loudly" do
    expect_raises(Shell::AutoComplete::ParseError, /--env: deletion is disabled .*hash_operations: false.*PATH=VALUE to assign/) do
      HashPolishCli.parse(["--env", "-PATH"])
    end
  end
end

describe "hash entry error messages" do
  it "suggests both readings for -key=value" do
    expect_raises(Shell::AutoComplete::ParseError, /invalid hash entry: -foo=bar \(use foo=bar to assign, or -foo to delete\)/) do
      HashPolishCli.parse(["--conf", "-foo=bar"])
    end
  end
end
