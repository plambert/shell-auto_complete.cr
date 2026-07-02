require "../spec_helper"

# A subcommand that answers to its canonical name and two aliases.
Shell::AutoComplete.command AliasMove,
  name: "move",
  aliases: ["mv", "rename"],
  description: "Move or rename a file" do
  flag force : Bool = false, "--force", "Overwrite the destination"
  positionals args : Array(String), "source and dest"

  property ran : Bool = false

  def run
    @ran = true
  end
end

# A second subcommand with no aliases, to confirm they don't leak.
Shell::AutoComplete.command AliasRemove,
  name: "remove",
  description: "Remove a file" do
  property ran : Bool = false

  def run
    @ran = true
  end
end

Shell::AutoComplete.command AliasRoot,
  name: "files",
  description: "Manage files" do
  subcommand AliasMove
  subcommand AliasRemove
end

describe "subcommand aliases" do
  it "routes the canonical name" do
    inst = AliasRoot.dispatch(["move", "a", "b"])
    inst.should be_a(AliasMove)
    inst.as(AliasMove).args.should eq(["a", "b"])
    inst.as(AliasMove).ran.should be_true
  end

  it "routes each alias to the same command" do
    ["mv", "rename"].each do |name|
      inst = AliasRoot.dispatch([name, "a", "b"])
      inst.should be_a(AliasMove)
      inst.as(AliasMove).args.should eq(["a", "b"])
    end
  end

  it "still rejects an unknown token that is neither a name nor an alias" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown subcommand: cp/) do
      AliasRoot.dispatch(["cp", "a", "b"], rescue_errors: false)
    end
  end

  it "exposes the declared aliases via command_aliases" do
    AliasMove.command_aliases.should eq(["mv", "rename"])
  end

  it "defaults to no aliases when none are declared" do
    AliasRemove.command_aliases.should be_empty
  end

  it "resolves both name and aliases through subcommand_named" do
    AliasRoot.subcommand_named("move").should eq(AliasMove)
    AliasRoot.subcommand_named("mv").should eq(AliasMove)
    AliasRoot.subcommand_named("rename").should eq(AliasMove)
    AliasRoot.subcommand_named("nope").should be_nil
  end

  it "lists the aliases beside the canonical name in help" do
    text = AliasRoot.help
    text.should contain("move, mv, rename")
    text.should contain("Move or rename a file")
    # A command without aliases shows just its name.
    text.should contain("remove")
    text.should_not contain("remove, ")
  end

  it "offers the canonical name and every alias in completion" do
    output = IO::Memory.new
    AliasRoot.dispatch(["__complete", "1", "files", ""], stdout: output)
    lines = output.to_s.lines
    lines.should contain("move")
    lines.should contain("mv")
    lines.should contain("rename")
    lines.should contain("remove")
  end

  it "filters completion candidates by prefix across names and aliases" do
    output = IO::Memory.new
    AliasRoot.dispatch(["__complete", "1", "files", "m"], stdout: output)
    output.to_s.lines.sort!.should eq(["move", "mv"])
  end

  it "descends into a subcommand referenced by an alias during completion" do
    # The alias occupies position 1, so completion descends into AliasMove and
    # offers its flag — proving the Dispatcher resolved the alias, not just the
    # canonical name.
    output = IO::Memory.new
    AliasRoot.dispatch(["__complete", "2", "files", "mv", "--"], stdout: output)
    output.to_s.lines.should contain("--force")
  end
end
