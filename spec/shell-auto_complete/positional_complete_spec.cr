require "../spec_helper"

FILES_DIRECTIVE = Shell::AutoComplete::Completion::Directive::FILES
DIRS_DIRECTIVE  = Shell::AutoComplete::Completion::Directive::DIRS

# Variadic path positional (the issue's example).
Shell::AutoComplete.command IdxCli, name: "idx", description: "x" do
  flag verbose : Bool = false, "--verbose", "-v"
  flag name : String?, "--name", "-n"
  positionals paths : Array(Path), "Directories to index"

  def run
  end
end

# Scalar leading path positional.
Shell::AutoComplete.command MoveCli, name: "mv2", description: "x" do
  positional src : Path, "source path"

  def run
  end
end

# A positional with a custom complete_with: method.
Shell::AutoComplete.command ColorCli, name: "colorcli", description: "x" do
  positional color : String, "a color", complete_with: :colors

  def self.colors(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
    %w[red green blue]
  end

  def run
  end
end

describe "runtime __complete: path positionals" do
  it "emits the files directive for an Array(Path) positional" do
    output = IO::Memory.new
    IdxCli.dispatch(["__complete", "1", "idx", "/Con"], stdout: output)
    output.to_s.lines.map(&.strip).should eq([FILES_DIRECTIVE])
  end

  it "emits the files directive at an empty positional slot" do
    output = IO::Memory.new
    IdxCli.dispatch(["__complete", "1", "idx", ""], stdout: output)
    output.to_s.lines.map(&.strip).should eq([FILES_DIRECTIVE])
  end

  it "keeps emitting the files directive for further variadic slots" do
    output = IO::Memory.new
    IdxCli.dispatch(["__complete", "2", "idx", "/etc", "/Con"], stdout: output)
    output.to_s.lines.map(&.strip).should eq([FILES_DIRECTIVE])
  end

  it "still completes flag names when the cursor is on a dash token" do
    output = IO::Memory.new
    IdxCli.dispatch(["__complete", "1", "idx", "--"], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("--verbose")
    lines.should contain("--name")
    lines.should_not contain(FILES_DIRECTIVE)
  end

  it "does not treat a value-taking flag's value as a positional" do
    # Cursor is the value of --name, not a path positional.
    output = IO::Memory.new
    IdxCli.dispatch(["__complete", "2", "idx", "--name", ""], stdout: output)
    output.to_s.lines.map(&.strip).reject(&.empty?).should_not contain(FILES_DIRECTIVE)
  end

  it "resolves the positional slot past a value-taking flag and its value" do
    output = IO::Memory.new
    IdxCli.dispatch(["__complete", "3", "idx", "--name", "foo", "/Con"], stdout: output)
    output.to_s.lines.map(&.strip).should eq([FILES_DIRECTIVE])
  end

  it "resolves the positional slot past a bool flag (consumes no value)" do
    output = IO::Memory.new
    IdxCli.dispatch(["__complete", "2", "idx", "--verbose", "/Con"], stdout: output)
    output.to_s.lines.map(&.strip).should eq([FILES_DIRECTIVE])
  end
end

describe "runtime __complete: scalar path positional" do
  it "Path -> files directive for the first slot" do
    output = IO::Memory.new
    MoveCli.dispatch(["__complete", "1", "mv2", "s"], stdout: output)
    output.to_s.lines.map(&.strip).should eq([FILES_DIRECTIVE])
  end
end

# The File/Dir property-storage remap (so `positional x : Dir` compiles) is a
# separate pre-existing limitation; the type-level completers are exercised
# directly here so the directive wiring is covered for all three path types.
describe "path-type __arg_complete directives" do
  it "Path completes files and directories" do
    Path.__arg_complete("x").should eq([FILES_DIRECTIVE])
  end

  it "File completes files and directories" do
    File.__arg_complete("x").should eq([FILES_DIRECTIVE])
  end

  it "Dir completes directories only" do
    Dir.__arg_complete("x").should eq([DIRS_DIRECTIVE])
  end
end

describe "runtime __complete: positional complete_with:" do
  it "calls the named method for a positional slot" do
    output = IO::Memory.new
    ColorCli.dispatch(["__complete", "1", "colorcli", ""], stdout: output)
    lines = output.to_s.lines.map(&.strip)
    lines.should contain("red")
    lines.should contain("green")
    lines.should contain("blue")
  end
end
