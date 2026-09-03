require "../spec_helper"
require "log"

# Issue #14: shortcut_flags configuration — only:/except:/aliases:.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "./src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-scconf", ".cr", dir: "#{__DIR__}/../..")
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

Shell::AutoComplete.command SCConfCli, name: "scc", description: "x" do
  flag log_level : Log::Severity = Log::Severity::Notice, "--log-level", "Log level",
    shortcut_flags: {
      except:  [:none],
      aliases: {quiet: :warn, verbose: :info},
    }
end

enum SCOnlyChoice
  Alpha
  Beta
  Gamma
end

Shell::AutoComplete.command SCOnlyCli, name: "sco", description: "x" do
  flag choice : SCOnlyChoice = SCOnlyChoice::Alpha, "--choice", "Choice",
    shortcut_flags: {only: [:alpha, :beta]}
end

describe "shortcut_flags except:" do
  it "generates shortcuts for the kept cases" do
    SCConfCli.parse(["--debug"]).log_level.should eq(Log::Severity::Debug)
    SCConfCli.parse(["--error"]).log_level.should eq(Log::Severity::Error)
  end

  it "does not generate excluded shortcuts" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --none/) do
      SCConfCli.parse(["--none"])
    end
  end

  it "still accepts the excluded case as a value" do
    SCConfCli.parse(["--log-level", "none"]).log_level.should eq(Log::Severity::None)
  end
end

describe "shortcut_flags only:" do
  it "generates only the listed shortcuts" do
    SCOnlyCli.parse(["--beta"]).choice.should eq(SCOnlyChoice::Beta)
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --gamma/) do
      SCOnlyCli.parse(["--gamma"])
    end
  end
end

describe "shortcut_flags aliases:" do
  it "maps an alias switch to its target value" do
    SCConfCli.parse(["--quiet"]).log_level.should eq(Log::Severity::Warn)
    SCConfCli.parse(["--verbose"]).log_level.should eq(Log::Severity::Info)
  end

  it "resolves aliases against real shortcuts last-wins" do
    SCConfCli.parse(["--quiet", "--debug"]).log_level.should eq(Log::Severity::Debug)
    SCConfCli.parse(["--debug", "--quiet"]).log_level.should eq(Log::Severity::Warn)
  end

  it "counts alias spellings in flag_given?" do
    SCConfCli.parse(["--quiet"]).flag_given?(:log_level).should be_true
  end

  it "lists aliases in help with their target value" do
    rendered = SCConfCli.help
    rendered.should contain("--quiet")
    rendered.should contain("Same as --log-level warn")
  end

  it "offers aliases in completion" do
    SCConfCli.completion_candidates(["scc", "--qui"], 1, "--qui", "scc").should contain("--quiet")
  end
end

describe "shortcut_flags config validation" do
  it "rejects only: and except: together" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadBoth
        Alpha
        Beta
      end
      Shell::AutoComplete.command BadBothCli, name: "x", description: "x" do
        flag choice : BadBoth = BadBoth::Alpha, "--choice", shortcut_flags: {only: [:alpha], except: [:beta]}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("mutually exclusive")
  end

  it "rejects unknown enum cases in except:" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadCase
        Alpha
      end
      Shell::AutoComplete.command BadCaseCli, name: "x", description: "x" do
        flag choice : BadCase = BadCase::Alpha, "--choice", shortcut_flags: {except: [:bogus]}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("unknown enum case")
  end

  it "rejects unknown alias targets" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadTarget
        Alpha
      end
      Shell::AutoComplete.command BadTargetCli, name: "x", description: "x" do
        flag choice : BadTarget = BadTarget::Alpha, "--choice", shortcut_flags: {aliases: {fast: :bogus}}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("unknown enum case")
  end

  it "rejects unknown config keys" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadKey
        Alpha
      end
      Shell::AutoComplete.command BadKeyCli, name: "x", description: "x" do
        flag choice : BadKey = BadKey::Alpha, "--choice", shortcut_flags: {nope: [:alpha]}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("unknown shortcut_flags option")
  end

  it "registers alias names in the duplicate checker" do
    status, err = compile_fragment <<-FRAGMENT
      enum DupAliasEnum
        Alpha
      end
      Shell::AutoComplete.command DupAliasShortcut, name: "x", description: "x" do
        flag choice : DupAliasEnum = DupAliasEnum::Alpha, "--choice", shortcut_flags: {aliases: {fast: :alpha}}
        flag fast : Bool = false, "--fast", "Explicit fast"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --fast")
  end
end
