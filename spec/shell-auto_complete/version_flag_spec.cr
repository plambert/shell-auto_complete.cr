require "../spec_helper"

# tool_name / tool_version macros, the --version intercept, the
# disable_version_flag opt-out, and the version subcommand.

# Resolved the same way the library's fallback resolves it, so the spec does
# not hard-code the shard's current version.
SHARDS_PROJECT_VERSION = {{ `shards version`.strip.stringify }}

Shell::AutoComplete.command VersionDefaultCli, name: "vdefault", description: "x" do
  def run
  end
end

Shell::AutoComplete.command VersionExplicitCli, name: "vexplicit", description: "x" do
  tool_name "mytool"
  tool_version "1.2.3"

  def run
  end
end

module VersionedApp
  VERSION = "4.5.6"

  Shell::AutoComplete.command Inner, name: "vmod", description: "x" do
    def run
    end
  end
end

Shell::AutoComplete.command VersionOwnConstCli, name: "vown", description: "x" do
  VERSION = "7.8.9"

  def run
  end
end

Shell::AutoComplete.command VersionDisabledCli, name: "vdisabled", description: "x" do
  disable_version_flag

  def run
  end
end

Shell::AutoComplete.command VersionFlagClaimedCli, name: "vclaimed", description: "x" do
  class_property ran : Bool = false
  flag version : Bool = false, "--version", "App-defined version switch"

  def run
    self.class.ran = true
  end
end

Shell::AutoComplete.command VersionSubLeaf, name: "leaf", description: "x" do
  def run
  end
end

Shell::AutoComplete.command VersionRoutingCli, name: "vroot", description: "x" do
  tool_version "3.0.0"
  enable_version_subcommand
  subcommand VersionSubLeaf
end

Shell::AutoComplete.command VersionParentCli, name: "vparent", description: "x" do
  tool_version "5.0.0"
end

Shell::AutoComplete.command VersionChildCli, name: "vchild", description: "x", parent: VersionParentCli do
  def run
  end
end

private def dispatch_output(klass, argv : Array(String)) : String
  output = IO::Memory.new
  klass.dispatch(argv, stdout: output, rescue_errors: false)
  output.to_s
end

describe "--version intercept" do
  it "prints the command name and the shards-version fallback by default" do
    dispatch_output(VersionDefaultCli, ["--version"]).should eq("vdefault #{SHARDS_PROJECT_VERSION}\n")
  end

  it "uses tool_name and tool_version when set" do
    dispatch_output(VersionExplicitCli, ["--version"]).should eq("mytool 1.2.3\n")
  end

  it "picks up a VERSION constant from an enclosing namespace" do
    dispatch_output(VersionedApp::Inner, ["--version"]).should eq("vmod 4.5.6\n")
  end

  it "picks up a VERSION constant on the command class itself" do
    dispatch_output(VersionOwnConstCli, ["--version"]).should eq("vown 7.8.9\n")
  end

  it "is inherited through parent:" do
    dispatch_output(VersionChildCli, ["--version"]).should eq("vchild 5.0.0\n")
  end

  it "does not fire after --" do
    expect_raises(Shell::AutoComplete::ParseError, /too many positional/) do
      VersionDefaultCli.dispatch(["--", "--version"], rescue_errors: false)
    end
  end
end

describe "disabling --version" do
  it "disable_version_flag turns the intercept off" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --version/) do
      VersionDisabledCli.dispatch(["--version"], rescue_errors: false)
    end
  end

  it "a flag claiming the --version spelling wins over the intercept" do
    VersionFlagClaimedCli.ran = false
    output = IO::Memory.new
    inst = VersionFlagClaimedCli.dispatch(["--version"], stdout: output, rescue_errors: false)
    output.to_s.should be_empty
    inst.as(VersionFlagClaimedCli).version.should be_true
    VersionFlagClaimedCli.ran.should be_true
  end
end

describe "--version with subcommands" do
  it "fires at the root when no subcommand word is given" do
    dispatch_output(VersionRoutingCli, ["--version"]).should eq("vroot 3.0.0\n")
  end

  it "does not fire below the root" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --version/) do
      VersionRoutingCli.dispatch(["leaf", "--version"], rescue_errors: false)
    end
  end
end

describe "enable_version_subcommand" do
  it "lists the version subcommand in help" do
    rendered = VersionRoutingCli.help
    rendered.should contain("version")
    rendered.should contain("Print the program name and version")
  end

  it "offers the version subcommand in completion" do
    VersionRoutingCli.completion_candidates(["vroot", "ver"], 1, "ver", "vroot").should contain("version")
  end

  it "prints the same line as --version when run" do
    project_root = "#{__DIR__}/../.."
    src = <<-CR
      require "./src/shell-auto_complete"

      Shell::AutoComplete.command VersionBinCli, name: "vbin", description: "x" do
        tool_name "vbin"
        tool_version "2.7.1"
        enable_version_subcommand
      end

      VersionBinCli.dispatch(ARGV)
      CR
    src_file = File.tempfile("sac-version-src", ".cr", dir: project_root)
    bin_file = File.tempfile("sac-version-bin", dir: project_root)
    bin_file.close
    begin
      File.write(src_file.path, src)
      build = Process.run(
        "crystal",
        ["build", src_file.path, "--no-debug", "-o", bin_file.path],
        output: Process::Redirect::Close,
        error: Process::Redirect::Close,
      )
      raise "compile failed" unless build.success?
      sub_io = IO::Memory.new
      Process.run(bin_file.path, ["version"], output: sub_io).success?.should be_true
      sub_io.to_s.should eq("vbin 2.7.1\n")
      flag_io = IO::Memory.new
      Process.run(bin_file.path, ["--version"], output: flag_io).success?.should be_true
      flag_io.to_s.should eq("vbin 2.7.1\n")
    ensure
      src_file.delete
      File.delete(bin_file.path) if File.exists?(bin_file.path)
    end
  end
end
