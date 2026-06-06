require "../spec_helper"

# These commands previously failed to compile: the property was typed File/Dir
# while __arg_transform returns Path (issue #6). The storage remap fixes that.

# Scalar File + scalar Dir.
Shell::AutoComplete.command FdMove, name: "fdmove", description: "x" do
  positional src : File, "source file"
  positional dst : Dir, "destination dir"

  def run
  end
end

# Variadic File positional.
Shell::AutoComplete.command FdGather, name: "fdgather", description: "x" do
  positionals files : Array(File), "files"

  def run
  end
end

# Variadic Dir positional.
Shell::AutoComplete.command FdScan, name: "fdscan", description: "x" do
  positionals dirs : Array(Dir), "dirs"

  def run
  end
end

private FILES = Shell::AutoComplete::Completion::Directive::FILES
private DIRS  = Shell::AutoComplete::Completion::Directive::DIRS

describe "File/Dir positionals: compilation and storage" do
  it "stores a scalar File positional as a Path" do
    inst = FdMove.parse([__FILE__, __DIR__])
    inst.src.should be_a(Path)
    inst.src.to_s.should eq(__FILE__)
    inst.dst.should be_a(Path)
    inst.dst.to_s.should eq(__DIR__)
  end

  it "still runs the File existence check during transform" do
    expect_raises(ArgumentError, /file does not exist/) do
      FdMove.parse(["/no/such/file/here.xyz", __DIR__])
    end
  end

  it "still runs the Dir existence check during transform" do
    expect_raises(ArgumentError, /directory does not exist/) do
      FdMove.parse([__FILE__, "/no/such/dir/here"])
    end
  end

  it "stores a variadic File positional as an Array(Path)" do
    inst = FdGather.parse([__FILE__, __FILE__])
    inst.files.should be_a(Array(Path))
    inst.files.map(&.to_s).should eq([__FILE__, __FILE__])
  end
end

describe "File/Dir positionals: completion uses the declared type" do
  it "a scalar File slot emits the files directive" do
    output = IO::Memory.new
    FdMove.dispatch(["__complete", "1", "fdmove", "s"], stdout: output)
    output.to_s.lines.map(&.strip).should eq([FILES])
  end

  it "a scalar Dir slot emits the dirs directive (not files)" do
    output = IO::Memory.new
    FdMove.dispatch(["__complete", "2", "fdmove", "src", "d"], stdout: output)
    output.to_s.lines.map(&.strip).should eq([DIRS])
  end

  it "a variadic Dir slot emits the dirs directive (not files)" do
    output = IO::Memory.new
    FdScan.dispatch(["__complete", "1", "fdscan", "d"], stdout: output)
    output.to_s.lines.map(&.strip).should eq([DIRS])
  end
end
