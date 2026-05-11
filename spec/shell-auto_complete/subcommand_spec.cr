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
      SubParent.dispatch(["bogus"])
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
