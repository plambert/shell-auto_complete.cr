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

# Subcommand with its own flags, used to verify completion descends into it.
Shell::AutoComplete.command CompLeaf, name: "leaf", description: "x" do
  flag width : Int32?, "--width", "-w"
  flag wide : Bool = false, "--wide"
  flag name : String?, "--name", "-n"
end

# Intermediate subcommand that itself has subcommands (no flags of its own).
Shell::AutoComplete.command CompMid, name: "mid", description: "x" do
  subcommand CompLeaf
end

# Root for nested-routing tests: nest -> mid -> leaf.
Shell::AutoComplete.command CompNest, name: "nest", description: "x" do
  subcommand CompMid
end

enum CompSize
  Bytes
  Kilobytes
  Megabytes
end

# Plain enum flag with derived shortcut switches; canonical, alias, and short
# spellings all reach the same flag.
Shell::AutoComplete.command CompEnum, name: "cenum", description: "x" do
  flag unit : CompSize = CompSize::Bytes, %w[--unit --units], "-u", shortcut_flags: true
end

# shortcut_flags named-tuple config: except: drops a case, aliases: adds
# switch spellings.
Shell::AutoComplete.command CompEnumConf, name: "cenumconf", description: "x" do
  flag unit : CompSize = CompSize::Bytes, "--unit",
    shortcut_flags: {except: [:megabytes], aliases: {kb: :kilobytes}}
end

# An enum flag with complete_with: — the explicit completer must win over the
# derived enum member candidates.
Shell::AutoComplete.command CompEnumCw, name: "cenumcw", description: "x" do
  flag unit : CompSize = CompSize::Bytes, "--unit", complete_with: :unit_candidates

  def self.unit_candidates(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
    %w[custom-a custom-b]
  end
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

describe "runtime __complete: subcommand recursion" do
  it "still lists top-level subcommand names at cword 1" do
    output = IO::Memory.new
    CompNest.dispatch(["__complete", "1", "nest", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("mid")
  end

  it "lists a subcommand's flags when the cursor is inside it" do
    output = IO::Memory.new
    CompNest.dispatch(["__complete", "2", "nest", "mid", "leaf"], stdout: output)
    # cword 2 sits on the "leaf" token of [nest, mid, leaf]; after descending
    # into mid, the token at the cursor names the leaf subcommand.
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("leaf")
  end

  it "lists a leaf subcommand's flags at an empty cursor past it" do
    output = IO::Memory.new
    CompNest.dispatch(["__complete", "3", "nest", "mid", "leaf", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--width")
    lines.should contain("--wide")
    lines.should contain("--name")
  end

  it "lists a subcommand's flags when current is the bare -- prefix" do
    output = IO::Memory.new
    CompNest.dispatch(["__complete", "3", "nest", "mid", "leaf", "--"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--width")
    lines.should contain("--wide")
    lines.should contain("--name")
  end

  it "filters a leaf subcommand's flags by prefix" do
    output = IO::Memory.new
    CompNest.dispatch(["__complete", "3", "nest", "mid", "leaf", "--wi"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--width")
    lines.should contain("--wide")
    lines.should_not contain("--name")
  end

  it "lists an intermediate parent's own subcommand names" do
    output = IO::Memory.new
    CompNest.dispatch(["__complete", "2", "nest", "mid", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("leaf")
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

describe "runtime __complete: shortcut switches in flag names" do
  it "offers derived shortcut switches alongside the flag itself" do
    output = IO::Memory.new
    CompEnum.dispatch(["__complete", "1", "cenum", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--unit")
    lines.should contain("--bytes")
    lines.should contain("--kilobytes")
    lines.should contain("--megabytes")
  end

  it "prefix-filters shortcut switches" do
    output = IO::Memory.new
    CompEnum.dispatch(["__complete", "1", "cenum", "--k"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--kilobytes")
    lines.should_not contain("--bytes")
    lines.should_not contain("--megabytes")
    lines.should_not contain("--unit")
  end

  it "does not offer an except:-excluded case's switch" do
    output = IO::Memory.new
    CompEnumConf.dispatch(["__complete", "1", "cenumconf", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--bytes")
    lines.should contain("--kilobytes")
    lines.should_not contain("--megabytes")
  end

  it "offers alias switches from the shortcut_flags config" do
    output = IO::Memory.new
    CompEnumConf.dispatch(["__complete", "1", "cenumconf", "--k"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--kb")
    lines.should contain("--kilobytes")
  end
end

describe "runtime __complete: plain enum values" do
  it "offers all kebab-cased members after the canonical spelling" do
    output = IO::Memory.new
    CompEnum.dispatch(["__complete", "2", "cenum", "--unit", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("bytes")
    lines.should contain("kilobytes")
    lines.should contain("megabytes")
  end

  it "prefix-filters members" do
    output = IO::Memory.new
    CompEnum.dispatch(["__complete", "2", "cenum", "--unit", "k"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("kilobytes")
    lines.should_not contain("bytes")
    lines.should_not contain("megabytes")
  end

  it "matches the flag by an alias spelling" do
    output = IO::Memory.new
    CompEnum.dispatch(["__complete", "2", "cenum", "--units", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("bytes")
    lines.should contain("kilobytes")
    lines.should contain("megabytes")
  end

  it "matches the flag by its short form" do
    output = IO::Memory.new
    CompEnum.dispatch(["__complete", "2", "cenum", "-u", "m"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("megabytes")
    lines.should_not contain("bytes")
  end

  it "lets complete_with: win over derived enum candidates" do
    output = IO::Memory.new
    CompEnumCw.dispatch(["__complete", "2", "cenumcw", "--unit", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("custom-a")
    lines.should contain("custom-b")
    lines.should_not contain("bytes")
    lines.should_not contain("kilobytes")
  end
end
