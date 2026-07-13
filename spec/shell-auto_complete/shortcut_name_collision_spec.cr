require "../spec_helper"

# Enum shortcut switches where two constants kebab-case to the same spelling
# (KB and Kb both give --kb). Alias constants (same value) generate the
# switch once, owned by the first-declared constant; constants with
# different values are ambiguous and rejected at compile time with a
# pointer to except:.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "./src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-sccollide", ".cr", dir: "#{__DIR__}/../..")
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

enum CollisionUnit
  Auto =    0
  KB   = 1024
  Kb   = 1024
  MB   = 2048
end

Shell::AutoComplete.command CollisionCli, name: "collide", description: "x" do
  flag unit : CollisionUnit = CollisionUnit::Auto, "--unit", "Unit", shortcut_flags: true
end

# Routing setup: exercises the parent arity tables and the routing-union
# gathering of subcommand shortcut switches with alias constants present.
Shell::AutoComplete.command CollisionConvert, name: "convert", description: "Convert" do
  class_property last : String = ""
  flag unit : CollisionUnit = CollisionUnit::Auto, "--unit", "Unit", shortcut_flags: true

  def run
    self.class.last = "convert unit=#{unit}"
  end
end

Shell::AutoComplete.command CollisionRoot, name: "collider", description: "x" do
  subcommand CollisionConvert
end

describe "enum shortcut alias constants (same value, same switch spelling)" do
  it "parses the collapsed switch to the first-declared constant" do
    CollisionCli.parse(["--kb"]).unit.should eq(CollisionUnit::KB)
  end

  it "generates non-colliding shortcuts normally" do
    CollisionCli.parse(["--mb"]).unit.should eq(CollisionUnit::MB)
    CollisionCli.parse(["--auto"]).unit.should eq(CollisionUnit::Auto)
  end

  it "counts the collapsed switch in flag_given?" do
    CollisionCli.parse(["--kb"]).flag_given?(:unit).should be_true
    CollisionCli.parse([] of String).flag_given?(:unit).should be_false
  end

  it "shows the case list once each in the help placeholder" do
    CollisionCli.help.should contain("--unit auto|kb|mb")
  end

  it "offers each case once in value completion" do
    CollisionUnit.__arg_complete("").should eq(["auto", "kb", "mb"])
  end

  it "routes the collapsed switch before the subcommand word" do
    CollisionConvert.last = ""
    CollisionRoot.dispatch(["--kb", "convert"], stdout: IO::Memory.new, rescue_errors: false)
    CollisionConvert.last.should eq("convert unit=KB")
  end
end

describe "enum shortcut name collision with different values" do
  it "rejects the flag at compile time and suggests except:" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadUnit
        KB = 1024
        Kb = 2048
      end
      Shell::AutoComplete.command BadUnitCli, name: "x", description: "x" do
        flag unit : BadUnit = BadUnit::KB, "--unit", "Unit", shortcut_flags: true
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("shortcut_flags on flag unit")
    err.should contain("KB and Kb")
    err.should contain("--kb")
    err.should contain("shortcut_flags: {except: [:kb]}")
  end

  it "compiles when except: removes the colliding spelling" do
    status, _err = compile_fragment <<-FRAGMENT
      enum ExceptUnit
        KB   = 1024
        Kb   = 2048
        Auto =    0
      end
      Shell::AutoComplete.command ExceptUnitCli, name: "x", description: "x" do
        flag unit : ExceptUnit = ExceptUnit::Auto, "--unit", "Unit", shortcut_flags: {except: [:kb]}
      end
      FRAGMENT
    status.success?.should be_true
  end

  it "compiles when only: keeps a single colliding constant out" do
    status, _err = compile_fragment <<-FRAGMENT
      enum OnlyUnit
        KB   = 1024
        Kb   = 2048
        Auto =    0
      end
      Shell::AutoComplete.command OnlyUnitCli, name: "x", description: "x" do
        flag unit : OnlyUnit = OnlyUnit::Auto, "--unit", "Unit", shortcut_flags: {only: [:auto]}
      end
      FRAGMENT
    status.success?.should be_true
  end

  it "keeps distinct names with duplicate values on separate switches" do
    status, _err = compile_fragment <<-FRAGMENT
      enum DistinctUnit
        Kilobytes = 1024
        KB        = 1024
      end
      Shell::AutoComplete.command DistinctUnitCli, name: "x", description: "x" do
        flag unit : DistinctUnit = DistinctUnit::KB, "--unit", "Unit", shortcut_flags: true
      end
      FRAGMENT
    status.success?.should be_true
  end
end
