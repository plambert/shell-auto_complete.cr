require "../spec_helper"

# Leaf subcommand
Shell::AutoComplete.command SubChild, name: "child", description: "child command" do
  flag value : String?, "--value", "v"

  property ran_child : Bool = false

  def run
    @ran_child = true
  end
end

# Another leaf
Shell::AutoComplete.command SubOther, name: "other", description: "other command" do
  property ran_other : Bool = false

  def run
    @ran_other = true
  end
end

# Parent with two subcommands
Shell::AutoComplete.command SubParent, name: "parent", description: "parent command" do
  subcommand SubChild
  subcommand SubOther
end

# Sub-subcommand: deeper subcommand of SubChild — wait, SubChild has flags, so it can't have subcommands itself.
# Make a separate three-level chain:
Shell::AutoComplete.command Leaf, name: "leaf", description: "leaf" do
  property ran_leaf : Bool = false

  def run
    @ran_leaf = true
  end
end

Shell::AutoComplete.command Middle, name: "middle", description: "middle" do
  subcommand Leaf
end

Shell::AutoComplete.command Root, name: "root", description: "root" do
  subcommand Middle
end

describe "subcommand routing" do
  it "routes 'parent child --value x' to SubChild" do
    inst = SubParent.dispatch(["child", "--value", "x"])
    inst.should be_a(SubChild)
    inst.as(SubChild).value.should eq("x")
    inst.as(SubChild).ran_child.should be_true
  end

  it "routes 'parent other' to SubOther" do
    inst = SubParent.dispatch(["other"])
    inst.should be_a(SubOther)
    inst.as(SubOther).ran_other.should be_true
  end

  it "routes a three-level chain (root middle leaf)" do
    inst = Root.dispatch(["middle", "leaf"])
    inst.should be_a(Leaf)
    inst.as(Leaf).ran_leaf.should be_true
  end

  it "raises ParseError when the first arg is not a known subcommand" do
    expect_raises(Shell::AutoComplete::ParseError) do
      SubParent.dispatch(["bogus"], rescue_errors: false)
    end
  end

  it "lists subcommands in help" do
    text = SubParent.help
    text.should contain("Subcommands:")
    text.should contain("child")
    text.should contain("child command")
    text.should contain("other")
    text.should contain("other command")
  end
end

describe "empty argv on subcommand parent" do
  it "prints help on empty argv when subcommands exist" do
    io = IO::Memory.new
    SubParent.dispatch([] of String, stdout: io)
    io.to_s.should contain("Usage: parent")
  end
end

describe "subcommand --help routing" do
  it "subcommand --help prints the subcommand's help qualified with the parent, not the root's" do
    io = IO::Memory.new
    SubParent.dispatch(["child", "--help"], stdout: io)
    text = io.to_s
    text.should contain("Usage: parent child")
    text.should contain("child command")
    # The child's own help, not the parent's subcommand listing.
    text.should_not contain("Subcommands:")
  end

  it "subcommand -h does the same" do
    io = IO::Memory.new
    SubParent.dispatch(["child", "-h"], stdout: io)
    text = io.to_s
    text.should contain("Usage: parent child")
  end

  it "sub-subcommand --help prints the leaf's help qualified through the chain" do
    io = IO::Memory.new
    Root.dispatch(["middle", "leaf", "--help"], stdout: io)
    text = io.to_s
    text.should contain("Usage: root middle leaf")
    # The leaf's own help, not an intermediate's subcommand listing.
    text.should_not contain("Subcommands:")
  end

  it "root --help still prints the root's help" do
    io = IO::Memory.new
    SubParent.dispatch(["--help"], stdout: io)
    text = io.to_s
    text.should contain("Usage: parent")
  end

  it "unknown first token is rejected even when --help follows" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown subcommand: bogus/) do
      SubParent.dispatch(["bogus", "--help"], rescue_errors: false)
    end
  end

  it "subcommand --help with extra args ignores them" do
    io = IO::Memory.new
    SubParent.dispatch(["child", "--help", "--value", "x"], stdout: io)
    text = io.to_s
    text.should contain("Usage: parent child")
  end
end
