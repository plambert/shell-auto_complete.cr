require "../spec_helper"

# Issue #22: parent-level flag inheritance (via `parent:` on the command
# macro) and flags on routing commands.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-inherit", ".cr", dir: spec_tmp_dir)
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

Shell::AutoComplete.command InheritApp, name: "iapp", description: "Routing root" do
  class_property last_run : String = ""

  flag verbose : Bool = false, "--verbose", "-V", "Verbose output"
  flag server : String = "localhost", "--server", "Server address"
  flag init : Bool = false, "--init", "Initialize configuration"

  def run
    self.class.last_run = "root init=#{init}"
  end
end

Shell::AutoComplete.command InheritScan, name: "scan", description: "Scan things", parent: InheritApp do
  class_property last_run : String = ""

  flag target : String?, "--target", "Scan target"

  def run
    self.class.last_run = "scan verbose=#{verbose} server=#{server} target=#{target}"
  end
end

# A second level: scan's own subcommand inheriting through the chain.
Shell::AutoComplete.command InheritDeep, name: "deep", description: "Deep scan", parent: InheritScan do
  class_property last_run : String = ""

  def run
    self.class.last_run = "deep verbose=#{verbose} target=#{target}"
  end
end

Shell::AutoComplete.command InheritOverride, name: "louder", description: "Override leaf", parent: InheritApp do
  flag verbosity : Int32 = 0, "--verbose", "Verbosity level", override: true

  def run
  end
end

class InheritApp
  subcommand InheritScan
  subcommand InheritOverride
end

class InheritScan
  subcommand InheritDeep
end

describe "flag inheritance" do
  it "binds an inherited flag on the leaf instance" do
    inst = InheritScan.parse(["--verbose", "--target", "db"])
    inst.verbose.should be_true
    inst.target.should eq("db")
    inst.server.should eq("localhost")
  end

  it "inherits through multiple levels" do
    inst = InheritDeep.parse(["--verbose", "--target", "x"])
    inst.verbose.should be_true
    inst.target.should eq("x")
  end

  it "renders inherited flags under an Inherited options heading" do
    rendered = InheritScan.help
    rendered.should contain("Inherited options:")
    rendered.should contain("--server")
    options_at = rendered.index("Options:").not_nil!
    inherited_at = rendered.index("Inherited options:").not_nil!
    (options_at < inherited_at).should be_true
  end

  it "offers inherited flags in leaf completion" do
    candidates = InheritScan.completion_candidates(["scan", "--se"], 1, "--se", "scan")
    candidates.should contain("--server")
  end

  it "supports flag_given? on inherited flags" do
    InheritScan.parse(["--server", "remote"]).flag_given?(:server).should be_true
    InheritScan.parse([] of String).flag_given?(:server).should be_false
  end
end

describe "routing with shared flags" do
  it "accepts shared flags before the subcommand word" do
    InheritScan.last_run = ""
    InheritApp.dispatch(["--verbose", "scan", "--target", "db"], rescue_errors: false)
    InheritScan.last_run.should eq("scan verbose=true server=localhost target=db")
  end

  it "accepts shared flags after the subcommand word" do
    InheritScan.last_run = ""
    InheritApp.dispatch(["scan", "--verbose"], rescue_errors: false)
    InheritScan.last_run.should eq("scan verbose=true server=localhost target=")
  end

  it "consumes value-flag arguments while walking to the subcommand word" do
    InheritScan.last_run = ""
    InheritApp.dispatch(["--server", "remote", "scan"], rescue_errors: false)
    InheritScan.last_run.should eq("scan verbose=false server=remote target=")
  end

  it "routes through nested levels with interleaved flags" do
    InheritDeep.last_run = ""
    InheritApp.dispatch(["--verbose", "scan", "deep", "--target", "x"], rescue_errors: false)
    InheritDeep.last_run.should eq("deep verbose=true target=x")
  end

  it "rejects an unknown flag before the subcommand word" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --bogus/) do
      InheritApp.dispatch(["--bogus", "scan"], rescue_errors: false)
    end
  end

  it "rejects an unknown subcommand word" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown subcommand: nope/) do
      InheritApp.dispatch(["--verbose", "nope"], rescue_errors: false)
    end
  end
end

describe "flags on routing commands" do
  it "parses and runs the routing command when only flags are given" do
    InheritApp.last_run = ""
    InheritApp.dispatch(["--init"], rescue_errors: false)
    InheritApp.last_run.should eq("root init=true")
  end

  it "still shows help with empty argv" do
    output = IO::Memory.new
    InheritApp.dispatch([] of String, stdout: output, rescue_errors: false)
    output.to_s.should contain("Usage:")
  end

  it "still intercepts --help on the routing command" do
    output = IO::Memory.new
    InheritApp.dispatch(["--verbose", "--help"], stdout: output, rescue_errors: false)
    output.to_s.should contain("Usage:")
  end
end

describe "inherited flag overrides" do
  it "replaces an inherited flag at the leaf with override: true" do
    inst = InheritOverride.parse(["--verbose", "3"])
    inst.verbosity.should eq(3)
    inst.verbose.should be_false
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: -V/) do
      InheritOverride.parse(["-V"])
    end
  end

  it "rejects an inherited-flag collision without override:" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command CollideBase, name: "base", description: "x" do
        flag verbose : Bool = false, "--verbose", "Verbose"
      end
      Shell::AutoComplete.command CollideLeaf, name: "leaf", description: "x", parent: CollideBase do
        flag chatty : Bool = false, "--verbose", "Chatty"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --verbose")
    err.should contain("override: true")
  end
end

describe "completion descent with shared flags" do
  it "completes against the subcommand after interleaved flags" do
    output = IO::Memory.new
    Shell::AutoComplete::Completion::Dispatcher.handle(
      InheritApp, ["__complete", "3", "iapp", "--verbose", "scan", "--tar"], output)
    output.to_s.should contain("--target")
  end
end
