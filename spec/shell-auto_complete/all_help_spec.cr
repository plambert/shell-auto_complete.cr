require "../spec_helper"

# Reuse existing fixtures from subcommand_spec.cr by defining fresh ones here
# to avoid coupling. SubParent has two children (SubChild, SubOther);
# Root → Middle → Leaf is a 3-level chain.

Shell::AutoComplete.command AllHelpChild, name: "child", description: "the child" do
  flag value : String?, "--value", "-v", "child's value flag"
end

Shell::AutoComplete.command AllHelpOther, name: "other", description: "the other" do
end

Shell::AutoComplete.command AllHelpParent, name: "parent", description: "the parent" do
  subcommand AllHelpChild
  subcommand AllHelpOther
end

Shell::AutoComplete.command AllHelpLeaf, name: "leaf", description: "the leaf" do
end

Shell::AutoComplete.command AllHelpMiddle, name: "middle", description: "the middle" do
  subcommand AllHelpLeaf
end

Shell::AutoComplete.command AllHelpRoot, name: "root", description: "the root" do
  subcommand AllHelpMiddle
end

# A leaf-only command (no subcommands) — like the cat example
Shell::AutoComplete.command AllHelpLeafOnly, name: "leafonly", description: "no subs" do
  flag value : String?, "--value", "v"
end

describe "--all-help" do
  it "shows root help plus each child's help on a 2-level tree" do
    io = IO::Memory.new
    AllHelpParent.dispatch(["--all-help"], stdout: io)
    text = io.to_s
    text.should contain("==== parent ====")
    text.should contain("==== parent child ====")
    text.should contain("==== parent other ====")
    text.should contain("Usage: parent")
    text.should contain("Usage: parent child")
    text.should contain("Usage: parent other")
    text.should contain("child's value flag")
  end

  it "recurses through a 3-level chain" do
    io = IO::Memory.new
    AllHelpRoot.dispatch(["--all-help"], stdout: io)
    text = io.to_s
    text.should contain("==== root ====")
    text.should contain("==== root middle ====")
    text.should contain("==== root middle leaf ====")
  end

  it "works at an intermediate level, qualified from the dispatched root" do
    io = IO::Memory.new
    AllHelpRoot.dispatch(["middle", "--all-help"], stdout: io)
    text = io.to_s
    text.should contain("==== root middle ====")
    text.should contain("==== root middle leaf ====")
    # Root's own section is not printed — --all-help fired at the middle level.
    text.should_not contain("==== root ====")
  end

  it "rejects --all-help on a leaf command (no subcommands)" do
    expect_raises(Shell::AutoComplete::ParseError) do
      AllHelpLeafOnly.dispatch(["--all-help"], rescue_errors: false)
    end
  end

  it "rejects user-declared --all-help flag at compile time" do
    src = <<-CR
      require "./src/shell-auto_complete"
      Shell::AutoComplete.command BadAllHelp, name: "x", description: "x" do
        flag foo : String?, "--all-help", "x"
      end
      CR
    tmp = File.tempfile("sac-allhelp-reserved", ".cr",
      dir: File.expand_path("#{__DIR__}/../.."))
    begin
      File.write(tmp.path, src)
      result = Process.run("crystal",
        ["build", "--no-codegen", tmp.path],
        output: Process::Redirect::Close,
        error: Process::Redirect::Close)
      result.success?.should be_false
    ensure
      tmp.delete
    end
  end
end
