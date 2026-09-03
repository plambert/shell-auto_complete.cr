require "../spec_helper"
require "log"

# Issues #12 and #13: Bool? tri-state switches, long aliases on switches with
# per-alias negation, and flag_given? introspection.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-tristate", ".cr", dir: spec_tmp_dir)
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

Shell::AutoComplete.command TriStateCli, name: "tri", description: "x" do
  flag organized : Bool?, "--organized", "Mark records organized"
  flag dryrun : Bool = false, "--dryrun", "--dry-run", "-n", "Do not perform actions"
  flag title : String = "untitled", "--title", "--name", "-t", "Title"
  flag level : Log::Severity?, "--level", "Level", shortcut_flags: true
end

describe "Bool? tri-state switches" do
  it "is nil when not mentioned" do
    TriStateCli.parse([] of String).organized.should be_nil
  end

  it "sets true on the positive spelling" do
    TriStateCli.parse(["--organized"]).organized.should be_true
  end

  it "sets false on the --no- spelling" do
    TriStateCli.parse(["--no-organized"]).organized.should be_false
  end

  it "resolves repeated spellings last-wins" do
    TriStateCli.parse(["--organized", "--no-organized"]).organized.should be_false
  end
end

describe "switch aliases (Bool)" do
  it "accepts an alias spelling" do
    TriStateCli.parse(["--dry-run"]).dryrun.should be_true
  end

  it "negates via the alias spelling" do
    TriStateCli.parse(["--dryrun", "--no-dry-run"]).dryrun.should be_false
  end

  it "negates the canonical as before" do
    TriStateCli.parse(["--dryrun", "--no-dryrun"]).dryrun.should be_false
  end

  it "lists alias spellings in help" do
    TriStateCli.help.should contain("--dry-run")
  end

  it "offers alias negations in completion" do
    candidates = TriStateCli.completion_candidates(["tri", "--no-d"], 1, "--no-d", "tri")
    candidates.should contain("--no-dryrun")
    candidates.should contain("--no-dry-run")
  end

  it "rejects an alias negation colliding with an explicit flag at compile time" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command DupAliasNegation, name: "x", description: "x" do
        flag dryrun : Bool = false, "--dryrun", "--dry-run", "Dry run"
        flag no_dry_run : String?, "--no-dry-run", "Explicit spelling"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --no-dry-run")
  end
end

describe "flag_given?" do
  it "is false for an untouched flag" do
    inst = TriStateCli.parse([] of String)
    inst.flag_given?(:organized).should be_false
    inst.flag_given?(:title).should be_false
  end

  it "distinguishes an explicit --no- from silence" do
    TriStateCli.parse(["--no-organized"]).flag_given?(:organized).should be_true
  end

  it "sees the canonical, alias, and short spellings of a value flag" do
    TriStateCli.parse(["--title", "x"]).flag_given?(:title).should be_true
    TriStateCli.parse(["--name=x"]).flag_given?(:title).should be_true
    TriStateCli.parse(["-t", "x"]).flag_given?(:title).should be_true
  end

  it "is true even when the explicit value equals the default" do
    TriStateCli.parse(["--title", "untitled"]).flag_given?(:title).should be_true
  end

  it "sees switch alias and short spellings" do
    TriStateCli.parse(["--no-dry-run"]).flag_given?(:dryrun).should be_true
    TriStateCli.parse(["-n"]).flag_given?(:dryrun).should be_true
  end

  it "sees enum shortcut spellings" do
    TriStateCli.parse(["--warn"]).flag_given?(:level).should be_true
  end

  it "accepts a String name" do
    TriStateCli.parse(["--organized"]).flag_given?("organized").should be_true
  end

  it "raises on an unknown flag name" do
    expect_raises(ArgumentError, /no flag named bogus/) do
      TriStateCli.parse([] of String).flag_given?(:bogus)
    end
  end
end
