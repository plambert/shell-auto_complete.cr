require "../spec_helper"

Shell::AutoComplete.command PosCli, name: "pos", description: "x" do
  positional name : String, "the name"
end

Shell::AutoComplete.command MultiPosCli, name: "m", description: "x" do
  positional first : String, "first"
  positional second : String?, "second optional"
end

Shell::AutoComplete.command TypedPosCli, name: "tp", description: "x" do
  positional port : Int32, "port", range: 1..65535
end

Shell::AutoComplete.command DashCli, name: "d", description: "x" do
  flag message : String?, "--message", "m"
  positional rest : String, "rest"
end

describe "positional macro (scalar)" do
  it "binds a single required positional" do
    PosCli.parse(["alice"]).name.should eq("alice")
  end

  it "errors when a required positional is missing" do
    expect_raises(Shell::AutoComplete::ParseError, /missing/) do
      PosCli.parse([] of String)
    end
  end

  it "binds multiple positionals in declaration order" do
    inst = MultiPosCli.parse(["a", "b"])
    inst.first.should eq("a")
    inst.second.should eq("b")
  end

  it "leaves a trailing optional positional nil when missing" do
    inst = MultiPosCli.parse(["a"])
    inst.first.should eq("a")
    inst.second.should be_nil
  end

  it "applies type transformer to positionals" do
    TypedPosCli.parse(["8080"]).port.should eq(8080)
  end

  it "applies validator to positionals" do
    expect_raises(Shell::AutoComplete::ParseError, /out of range/) do
      TypedPosCli.parse(["70000"])
    end
  end

  it "rejects extra positionals when no variadic" do
    expect_raises(Shell::AutoComplete::ParseError, /too many/) do
      PosCli.parse(["alice", "extra"])
    end
  end

  it "respects -- as end of flag parsing" do
    inst = DashCli.parse(["--message", "hi", "--", "--not-a-flag"])
    inst.message.should eq("hi")
    inst.rest.should eq("--not-a-flag")
  end
end
