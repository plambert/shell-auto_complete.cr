require "../spec_helper"

# Issue #10: compile-time duplicate flag-name detection and `override: true`.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-dupflag", ".cr", dir: spec_tmp_dir)
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

# A shared flag set, as a mixin macro — the composition pattern the override
# option exists for.
macro dup_spec_common_flags
  flag verbose : Bool = false, "--verbose", "-v", "Verbose output"
end

Shell::AutoComplete.command DupOverrideCli, name: "dupov", description: "x" do
  dup_spec_common_flags
  flag verbosity : Int32 = 0, "--verbose", "Verbosity level", override: true
  flag color : Bool = false, "--color", "Colorize"
end

describe "duplicate flag detection" do
  it "rejects the same canonical declared twice" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command DupCanonical, name: "x", description: "x" do
        flag alpha : String?, "--thing", "First"
        flag beta : String?, "--thing", "Second"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --thing")
    err.should contain("already declared by flag `alpha`")
    err.should contain("override: true")
  end

  it "rejects an alias colliding with another flag's canonical" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command DupAlias, name: "x", description: "x" do
        flag alpha : String?, "--thing", "First"
        flag beta : String?, "--other", "--thing", "Second"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --thing")
  end

  it "rejects two flags claiming the same short form" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command DupShort, name: "x", description: "x" do
        flag alpha : String?, "--alpha", "-a", "First"
        flag beta : String?, "--beta", "-a", "Second"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name -a")
  end

  it "rejects an explicit flag colliding with a generated --no- negation" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command DupNegation, name: "x", description: "x" do
        flag covers : Bool = false, "--covers", "Include covers"
        flag no_covers : String?, "--no-covers", "Explicit spelling"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --no-covers")
    err.should contain("already declared by flag `covers`")
  end

  it "rejects a generated negation colliding with an earlier explicit flag" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command DupNegationReverse, name: "x", description: "x" do
        flag no_covers : String?, "--no-covers", "Explicit spelling"
        flag covers : Bool = false, "--covers", "Include covers"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --no-covers")
  end

  it "rejects an explicit flag colliding with an enum shortcut switch" do
    status, err = compile_fragment <<-FRAGMENT
      enum DupSpeed
        Slow
        FullSpeed
      end
      Shell::AutoComplete.command DupShortcut, name: "x", description: "x" do
        flag speed : DupSpeed = DupSpeed::Slow, "--speed", "Speed", shortcut_flags: true
        flag full_speed : Bool = false, "--full-speed", "Explicit spelling"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --full-speed")
  end

  it "allows a non-negatable switch to coexist with an explicit --no- flag" do
    status, _err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command OkNonNegatable, name: "x", description: "x" do
        flag covers : Bool = false, "--covers", "Include covers", negatable: false
        flag no_covers : String?, "--no-covers", "Explicit spelling"
      end
      FRAGMENT
    status.success?.should be_true
  end

  it "rejects override: true that matches no existing flag" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadOverride, name: "x", description: "x" do
        flag alpha : String?, "--alpha", "First", override: true
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("override: true")
    err.should contain("match an existing flag")
  end

  it "rejects an override reusing the replaced flag's property name" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command SameVarOverride, name: "x", description: "x" do
        flag verbose : Bool = false, "--verbose", "Verbose"
        flag verbose : Bool = false, "--verbose", "Louder", override: true
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("new property name")
  end
end

describe "flag override" do
  it "binds the overriding flag's property" do
    inst = DupOverrideCli.parse(["--verbose", "3"])
    inst.verbosity.should eq(3)
    inst.verbose.should be_false
  end

  it "frees the replaced flag's other spellings" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: -v/) do
      DupOverrideCli.parse(["-v"])
    end
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --no-verbose/) do
      DupOverrideCli.parse(["--no-verbose"])
    end
  end

  it "renders only the replacement in help" do
    rendered = DupOverrideCli.help
    rendered.should contain("Verbosity level")
    rendered.should_not contain("Verbose output")
  end

  it "offers only the replacement in completion" do
    candidates = DupOverrideCli.completion_candidates(["dupov", "--ver"], 1, "--ver", "dupov")
    candidates.should eq(["--verbose"])
  end

  it "leaves unrelated flags untouched" do
    DupOverrideCli.parse(["--color"]).color.should be_true
  end
end
