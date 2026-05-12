require "../spec_helper"

# Case 1: leading scalar + variadic
Shell::AutoComplete.command VarCli1, name: "v1", description: "x" do
  positional name : String, "n"
  positionals files : Array(Path), "files", min: 1
end

# Case for max enforcement
Shell::AutoComplete.command VarMaxCli, name: "vm", description: "x" do
  positionals items : Array(String), "items", min: 1, max: 3
end

# Case 2: variadic + trailing scalar
Shell::AutoComplete.command VarCli2, name: "v2", description: "x" do
  positionals files : Array(Path), "files"
  positional destination : Path, "dest"
end

# Case 3: leading + variadic + trailing
Shell::AutoComplete.command VarCli3, name: "v3", description: "x" do
  positional name : String, "n"
  positionals files : Array(Path), "files"
  positional destination : Path, "dest"
end

# Case 4: bare variadic
Shell::AutoComplete.command VarCli4, name: "v4", description: "x" do
  positionals tags : Array(String), "tags"
end

describe "positionals (variadic)" do
  it "binds leading scalar + variadic" do
    inst = VarCli1.parse(["alpha", "a.txt", "b.txt"])
    inst.name.should eq("alpha")
    inst.files.size.should eq(2)
    inst.files.map(&.to_s).should eq(["a.txt", "b.txt"])
  end

  it "enforces variadic min" do
    expect_raises(Shell::AutoComplete::ParseError) do
      VarCli1.parse(["alpha"]) # min: 1 but no files
    end
  end

  it "binds variadic + trailing scalar (empty variadic OK by default)" do
    inst = VarCli2.parse(["dest"])
    inst.files.empty?.should be_true
    inst.destination.to_s.should eq("dest")
  end

  it "binds variadic + trailing scalar (populated variadic)" do
    inst = VarCli2.parse(["a.txt", "b.txt", "dest"])
    inst.files.map(&.to_s).should eq(["a.txt", "b.txt"])
    inst.destination.to_s.should eq("dest")
  end

  it "binds leading + variadic + trailing (empty variadic)" do
    inst = VarCli3.parse(["a", "dest"])
    inst.name.should eq("a")
    inst.files.empty?.should be_true
    inst.destination.to_s.should eq("dest")
  end

  it "binds leading + variadic + trailing (populated)" do
    inst = VarCli3.parse(["a", "x", "y", "dest"])
    inst.name.should eq("a")
    inst.files.map(&.to_s).should eq(["x", "y"])
    inst.destination.to_s.should eq("dest")
  end

  it "errors when too few tokens" do
    expect_raises(Shell::AutoComplete::ParseError) do
      VarCli3.parse(["a"]) # need at least name + destination = 2 tokens
    end
  end

  it "binds a bare variadic (zero tokens)" do
    inst = VarCli4.parse([] of String)
    inst.tags.empty?.should be_true
  end

  it "binds a bare variadic (multiple tokens)" do
    inst = VarCli4.parse(["a", "b", "c"])
    inst.tags.should eq(["a", "b", "c"])
  end
end

describe "max enforcement on variadic positionals" do
  it "rejects more than max variadic args" do
    expect_raises(Shell::AutoComplete::ParseError, /too many/) do
      VarMaxCli.parse(["a", "b", "c", "d"])
    end
  end

  it "accepts up to max" do
    VarMaxCli.parse(["a", "b", "c"]).items.should eq(%w[a b c])
  end

  it "accepts at min" do
    VarMaxCli.parse(["a"]).items.should eq(%w[a])
  end
end
