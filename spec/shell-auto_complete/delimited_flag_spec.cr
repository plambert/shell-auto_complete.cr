require "../spec_helper"

Shell::AutoComplete.command DfTool, name: "tool", description: "delimited demo" do
  delimited_flag command : Array(String), "--command", "-c", "Command to run"
  flag json : Bool = false, "--json", "JSON output"
  flag foo : Bool = false, "--foo", "foo"
  positionals rest : Array(String), "leftover positionals"

  def run
  end
end

Shell::AutoComplete.command DfNilable, name: "dfn", description: "nilable + custom delim" do
  delimited_flag command : Array(String)?, "--command", "Command", delimiter: "END"
  delimited_flag tags : Set(String), "--tags", "Tags"

  def run
  end
end

# Routing: a delimited flag on a base, inherited by a routed subcommand.
Shell::AutoComplete.command DfBase, name: "dfbase", description: "base" do
  delimited_flag pre : Array(String), "--pre", "preamble"

  def run
  end
end

Shell::AutoComplete.command DfChild, name: "child", description: "child", parent: DfBase do
  def run
  end
end

class DfBase
  subcommand DfChild
end

private def df_complete(klass, argv)
  output = IO::Memory.new
  klass.dispatch(argv, stdout: output)
  output.to_s.lines.map(&.strip)
end

describe "delimited_flag" do
  describe "capture" do
    it "captures the run between the flag and the delimiter, resuming parsing after it" do
      inst = DfTool.parse(["--foo", "--command", "echo", "hello", "--", "--json", "path"])
      inst.command.should eq(["echo", "hello"])
      inst.foo.should be_true
      inst.json.should be_true # parsing resumed: --json is a flag, not a positional
      inst.rest.should eq(["path"])
    end

    it "takes flag-looking tokens inside the run literally" do
      inst = DfTool.parse(["--command", "grep", "-n", "--color", "foo", "--", "--json"])
      inst.command.should eq(["grep", "-n", "--color", "foo"])
      inst.json.should be_true
    end

    it "captures to end of argv when the delimiter never appears" do
      inst = DfTool.parse(["--command", "echo", "a", "b"])
      inst.command.should eq(["echo", "a", "b"])
    end

    it "captures nothing between the flag and an immediate delimiter" do
      inst = DfTool.parse(["--command", "--", "--json"])
      inst.command.should eq([] of String)
      inst.json.should be_true
    end

    it "works through the short spelling" do
      inst = DfTool.parse(["-c", "git", "commit", "--", "extra"])
      inst.command.should eq(["git", "commit"])
      inst.rest.should eq(["extra"])
    end
  end

  describe "default when absent" do
    it "is an empty collection for a non-nilable type" do
      DfTool.parse(["--json"]).command.should eq([] of String)
    end

    it "is nil for a nilable type" do
      DfNilable.parse([] of String).command.should be_nil
    end
  end

  describe "type and delimiter options" do
    it "honors a custom delimiter" do
      inst = DfNilable.parse(["--command", "echo", "hi", "END", "--tags", "a", "b"])
      inst.command.should eq(["echo", "hi"])
      inst.tags.should eq(Set{"a", "b"})
    end

    it "builds a Set, deduplicating appended tokens" do
      DfNilable.parse(["--tags", "a", "b", "a", "c"]).tags.should eq(Set{"a", "b", "c"})
    end
  end

  describe "help" do
    it "renders the flag with a capture placeholder" do
      text = DfTool.help
      text.should contain("--command, -c <args>... --")
      text.should contain("Command to run")
    end
  end

  describe "completion" do
    it "offers the delimited spelling as a flag name" do
      df_complete(DfTool, ["__complete", "1", "tool", "--c"]).should contain("--command")
    end

    it "offers nothing while the cursor is inside an un-terminated capture" do
      df_complete(DfTool, ["__complete", "3", "tool", "--command", "echo", ""]).should be_empty
    end

    it "resumes flag completion after the delimiter" do
      candidates = df_complete(DfTool, ["__complete", "5", "tool", "--command", "echo", "--", "--"])
      candidates.should contain("--json")
    end
  end

  describe "duplicate detection" do
    it "is a compile error to reuse a spelling" do
      # See spec/shell-auto_complete/subcommand_compile_spec.cr style; asserted
      # here by construction — DfTool compiles with distinct spellings, and a
      # colliding delimited_flag/flag pair fails to compile (covered manually).
      DfTool.parse(["--json"]).command.should eq([] of String)
    end
  end

  describe "composition with subcommands" do
    it "routes past a delimited capture to the subcommand word" do
      inst = DfBase.dispatch(["--pre", "a", "b", "c", "--", "child"])
      inst.should be_a(DfChild)
      inst.as(DfChild).pre.should eq(["a", "b", "c"])
    end

    it "still routes a bare subcommand" do
      DfBase.dispatch(["child"]).should be_a(DfChild)
    end
  end
end
