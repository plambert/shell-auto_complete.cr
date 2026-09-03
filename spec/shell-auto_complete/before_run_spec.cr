require "../spec_helper"

# before_run hooks: setup collected down the class hierarchy, run parent-first
# between parse and run, with ArgumentError surfacing as a clean ParseError.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-beforerun", ".cr", dir: spec_tmp_dir)
  begin
    File.write(tmp.path, src)
    error_io = IO::Memory.new
    status = Process.run("crystal", ["build", "--no-debug", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: error_io)
    {status, error_io.to_s}
  ensure
    tmp.delete
  end
end

Shell::AutoComplete.command BeforeRunBasic, name: "basic", description: "x" do
  class_property log : Array(String) = [] of String

  flag fail : Bool = false, "--fail", "Make the hook fail"

  property resolved : String = ""

  before_run do
    raise ArgumentError.new("hook said no") if fail
    @resolved = "resolved"
    self.class.log << "hook"
  end

  def run
    self.class.log << "run(#{resolved})"
  end
end

# Two hooks in one class run in declaration order.
Shell::AutoComplete.command BeforeRunMulti, name: "multi", description: "x" do
  class_property log : Array(String) = [] of String

  before_run { self.class.log << "first" }
  before_run { self.class.log << "second" }

  def run
    self.class.log << "run"
  end
end

# Hooks collected down the hierarchy, parent-first.
Shell::AutoComplete.command BeforeRunParent, name: "parent", description: "x" do
  class_property log : Array(String) = [] of String

  flag verbose : Bool = false, "--verbose", "Verbose"

  before_run { BeforeRunParent.log << "parent(verbose=#{verbose})" }
end

Shell::AutoComplete.command BeforeRunChild, name: "child", description: "x", parent: BeforeRunParent do
  before_run { BeforeRunParent.log << "child" }

  def run
    BeforeRunParent.log << "run"
  end
end

describe "before_run" do
  it "runs the hook before run, with parsed flags visible" do
    BeforeRunBasic.log = [] of String
    inst = BeforeRunBasic.dispatch([] of String, rescue_errors: false).as(BeforeRunBasic)
    BeforeRunBasic.log.should eq(["hook", "run(resolved)"])
    inst.resolved.should eq("resolved")
  end

  it "converts an ArgumentError from the hook into a ParseError" do
    BeforeRunBasic.log = [] of String
    expect_raises(Shell::AutoComplete::ParseError, /hook said no/) do
      BeforeRunBasic.dispatch(["--fail"], rescue_errors: false)
    end
    BeforeRunBasic.log.should be_empty
  end

  it "carries the command path on the converted error" do
    expect_raises(Shell::AutoComplete::ParseError) do
      begin
        BeforeRunBasic.dispatch(["--fail"], rescue_errors: false)
      rescue ex : Shell::AutoComplete::ParseError
        ex.command_path.should eq("basic")
        raise ex
      end
    end
  end

  it "runs multiple hooks in declaration order" do
    BeforeRunMulti.log = [] of String
    BeforeRunMulti.dispatch([] of String, rescue_errors: false)
    BeforeRunMulti.log.should eq(["first", "second", "run"])
  end

  it "runs inherited hooks parent-first, then the child's" do
    BeforeRunParent.log = [] of String
    BeforeRunChild.dispatch(["--verbose"], rescue_errors: false)
    BeforeRunParent.log.should eq(["parent(verbose=true)", "child", "run"])
  end

  it "does not run hooks when parsing fails" do
    BeforeRunBasic.log = [] of String
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag/) do
      BeforeRunBasic.dispatch(["--nonexistent"], rescue_errors: false)
    end
    BeforeRunBasic.log.should be_empty
  end

  it "does not run hooks for a help request" do
    BeforeRunBasic.log = [] of String
    output = IO::Memory.new
    BeforeRunBasic.dispatch(["--help"], stdout: output, rescue_errors: false)
    BeforeRunBasic.log.should be_empty
    output.to_s.should contain("Usage:")
  end

  it "rejects a block with arguments at compile time" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadHook, name: "x", description: "x" do
        before_run do |arg|
        end
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("takes no arguments")
  end
end
