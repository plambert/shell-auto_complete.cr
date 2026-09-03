require "../spec_helper"

# Routing union (issue #22 follow-up): a parent routes past a flag that only
# some subcommands declare, so `foo --format json list` reaches `list` (which
# has --format) while `foo --format json status` is rejected at `status`
# (which does not). The parent learns subcommand flag arities at macro time;
# the accept/reject decision stays with the chosen subcommand.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-routeunion", ".cr", dir: spec_tmp_dir)
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

enum RUFmt
  Table
  Json
end

Shell::AutoComplete.command RuList, name: "list", description: "List" do
  class_property last : String = ""
  flag format : RUFmt = RUFmt::Table, "--format", "Output format"
  flag quiet : Bool = false, "--quiet", "-q", "Quiet"

  def run
    self.class.last = "list format=#{format} quiet=#{quiet}"
  end
end

Shell::AutoComplete.command RuStatus, name: "status", description: "Status" do
  def run
  end
end

Shell::AutoComplete.command RuInspect, name: "inspect", description: "Inspect" do
  flag format : RUFmt = RUFmt::Table, "--format", "Output format"

  def run
  end
end

Shell::AutoComplete.command RuFoo, name: "foo", description: "Foo tool" do
  subcommand RuList
  subcommand RuStatus
  subcommand RuInspect
end

private def dispatch(klass, argv : Array(String))
  klass.dispatch(argv, stdout: IO::Memory.new, rescue_errors: false)
end

describe "routing past a subcommand-only flag" do
  it "routes a value flag (and its value) before the subcommand word" do
    RuList.last = ""
    dispatch(RuFoo, ["--format", "json", "list"])
    RuList.last.should eq("list format=Json quiet=false")
  end

  it "routes the =-joined form" do
    RuList.last = ""
    dispatch(RuFoo, ["--format=json", "list"])
    RuList.last.should eq("list format=Json quiet=false")
  end

  it "routes a short value flag before the word" do
    RuList.last = ""
    dispatch(RuFoo, ["list", "--format", "json"])
    RuList.last.should eq("list format=Json quiet=false")
  end

  it "routes a switch before the word without consuming a value" do
    RuList.last = ""
    dispatch(RuFoo, ["-q", "list"])
    RuList.last.should eq("list format=Table quiet=true")
  end

  it "rejects the flag at the subcommand that did not declare it" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --format/) do
      dispatch(RuFoo, ["--format", "json", "status"])
    end
  end

  it "carries the subcommand's path on the rejection" do
    begin
      dispatch(RuFoo, ["--format", "json", "status"])
    rescue ex : Shell::AutoComplete::ParseError
      ex.command_path.should eq("foo status")
    end
  end

  it "still rejects a flag no subcommand declares, before the word, at the parent" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --bogus/) do
      dispatch(RuFoo, ["--bogus", "list"])
    end
  end

  it "shares one spelling across subcommands that agree on arity" do
    # --format is a value flag on both list and inspect; routing to inspect works.
    dispatch(RuFoo, ["--format", "json", "inspect"])
  end

  it "completes the subcommand's flags after a before-word flag" do
    output = IO::Memory.new
    Shell::AutoComplete::Completion::Dispatcher.handle(
      RuFoo, ["__complete", "4", "foo", "--format", "json", "list", "--qu"], output)
    output.to_s.should contain("--quiet")
  end
end

describe "routing-union arity conflict" do
  it "is a compile error when subcommands disagree on a spelling's arity" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command ConfA, name: "a", description: "x" do
        flag mode : String?, "--mode", "Mode value"
        def run; end
      end
      Shell::AutoComplete.command ConfB, name: "b", description: "x" do
        flag mode : Bool = false, "--mode", "Mode switch"
        def run; end
      end
      Shell::AutoComplete.command ConfRoot, name: "r", description: "x" do
        subcommand ConfA
        subcommand ConfB
      end
      ConfRoot.dispatch(["--help"])
      FRAGMENT
    status.success?.should be_false
    err.should contain("disagree on whether")
    err.should contain("--mode")
  end
end
