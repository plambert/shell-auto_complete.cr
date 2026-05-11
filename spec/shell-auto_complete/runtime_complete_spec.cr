require "../spec_helper"

Shell::AutoComplete.command CompCli, name: "comp", description: "x" do
  flag verbose : Bool = false, "--verbose", "-v"
  flag dryrun : Bool = false, %w[--dryrun --dry-run], "d"
end

@[Flags]
enum CompPerm
  Read
  Write
  Execute
end

Shell::AutoComplete.command FlagsComp, name: "fc", description: "x" do
  flag perms : CompPerm = CompPerm::None, "--perms", "p"
end

Shell::AutoComplete.command CompParent, name: "compparent", description: "x" do
  subcommand CompCli
end

describe "runtime __complete: flag names" do
  it "emits all flag forms when active word is empty" do
    output = IO::Memory.new
    CompCli.dispatch(["__complete", "1", "comp", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--verbose")
    lines.should contain("--no-verbose")
    lines.should contain("-v")
  end

  it "applies smart alias filtering when canonical matches prefix" do
    output = IO::Memory.new
    CompCli.dispatch(["__complete", "1", "comp", "--dry"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--dryrun")
    lines.should_not contain("--dry-run")
  end

  it "shows alias when canonical does NOT match prefix" do
    output = IO::Memory.new
    CompCli.dispatch(["__complete", "1", "comp", "--dry-"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--dry-run")
    lines.should_not contain("--dryrun")
  end
end

describe "runtime __complete: subcommands" do
  it "emits subcommand names when parent has subcommands" do
    output = IO::Memory.new
    CompParent.dispatch(["__complete", "1", "compparent", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("comp")
  end
end

describe "runtime __complete: @[Flags] trailing comma" do
  it "offers remaining cases after a comma" do
    output = IO::Memory.new
    FlagsComp.dispatch(["__complete", "2", "fc", "--perms", "read,"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("read,write")
    lines.should contain("read,execute")
    lines.should_not contain("read,read")
  end
end
