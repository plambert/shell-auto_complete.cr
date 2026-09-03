require "../spec_helper"

# Issue #55: shortcut_flags spellings that are not derived long forms — a
# dashed alias key used verbatim, a short beside an alias's long form, and a
# short attached to a generated case switch.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-scshort", ".cr", dir: spec_tmp_dir)
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

enum SCShortColor
  Auto
  On
  Off
end

Shell::AutoComplete.command SCDashKeyCli, name: "dashkey", description: "x" do
  flag color : SCShortColor = SCShortColor::Auto, "--color WHEN", "Colorize output",
    shortcut_flags: {
      except:  [:auto, :on, :off],
      aliases: {"-c": :on, "-C": :off},
    }
end

Shell::AutoComplete.command SCTupleCli, name: "tuple", description: "x" do
  flag color : SCShortColor = SCShortColor::Auto, "--color WHEN", "Colorize output",
    shortcut_flags: {
      except:  [:auto, :on, :off],
      aliases: {
        color_on:  {value: :on, short: "-c", description: "Force color on"},
        color_off: {value: :off, short: "-C"},
      },
    }
end

Shell::AutoComplete.command SCShortsCli, name: "shorts", description: "x" do
  flag color : SCShortColor = SCShortColor::Auto, "--color WHEN", "Colorize output",
    shortcut_flags: {except: [:auto], shorts: {on: "-c", off: "-C"}}
end

Shell::AutoComplete.command SCShortRoot, name: "shortroot", description: "root" do
  flag color : SCShortColor = SCShortColor::Auto, "--color WHEN", "Colorize output",
    shortcut_flags: {except: [:auto], shorts: {on: "-c"}}
end

Shell::AutoComplete.command SCShortSub, name: "sub", description: "child", parent: SCShortRoot do
  def run
  end
end

class SCShortRoot
  subcommand SCShortSub
end

describe "shortcut_flags with a dashed alias key" do
  it "uses the key verbatim as the spelling" do
    SCDashKeyCli.parse(["-c"]).color.should eq(SCShortColor::On)
    SCDashKeyCli.parse(["-C"]).color.should eq(SCShortColor::Off)
  end

  it "does not also generate a long form for the alias" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --c/) do
      SCDashKeyCli.parse(["--c"])
    end
  end

  it "leaves the excluded cases without their own switches" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --on/) do
      SCDashKeyCli.parse(["--on"])
    end
  end

  it "resolves against the flag's own value last-wins" do
    SCDashKeyCli.parse(["-c", "--color", "off"]).color.should eq(SCShortColor::Off)
    SCDashKeyCli.parse(["--color", "off", "-c"]).color.should eq(SCShortColor::On)
    SCDashKeyCli.parse(["-c", "-C"]).color.should eq(SCShortColor::Off)
  end

  it "counts toward flag_given?" do
    SCDashKeyCli.parse(["-c"]).flag_given?(:color).should be_true
    SCDashKeyCli.parse([] of String).flag_given?(:color).should be_false
  end

  it "records the spelling as typed in parsed_occurrences" do
    SCDashKeyCli.parse(["-c"]).parsed_occurrences.should eq([{"-c", nil}])
  end

  it "offers the short in completion" do
    SCDashKeyCli.completion_candidates(["dashkey", "-c"], 1, "-c", "dashkey").should contain("-c")
    SCDashKeyCli.completion_candidates(["dashkey", "-"], 1, "-", "dashkey").should contain("-C")
  end

  it "lists the short in help, indented under the flag it forces" do
    rendered = SCDashKeyCli.help
    rendered.should contain("  --color WHEN")
    rendered.should contain("      -c ")
    rendered.should contain("Same as --color on")
    rendered.should contain("Same as --color off")
  end
end

describe "shortcut_flags alias with value:/short:/description:" do
  it "accepts both the long form and the short" do
    SCTupleCli.parse(["--color-on"]).color.should eq(SCShortColor::On)
    SCTupleCli.parse(["-c"]).color.should eq(SCShortColor::On)
    SCTupleCli.parse(["--color-off"]).color.should eq(SCShortColor::Off)
    SCTupleCli.parse(["-C"]).color.should eq(SCShortColor::Off)
  end

  it "counts either spelling toward flag_given?" do
    SCTupleCli.parse(["--color-on"]).flag_given?(:color).should be_true
    SCTupleCli.parse(["-C"]).flag_given?(:color).should be_true
  end

  it "renders both spellings on one help row" do
    SCTupleCli.help.should contain("--color-on, -c")
  end

  it "uses the given description, falling back to the generated one" do
    rendered = SCTupleCli.help
    rendered.should contain("Force color on")
    rendered.should contain("Same as --color off")
  end

  it "offers both spellings in completion" do
    candidates = SCTupleCli.completion_candidates(["tuple", "-"], 1, "-", "tuple")
    candidates.should contain("-c")
    candidates.should contain("--color-on")
  end
end

describe "shortcut_flags shorts:" do
  it "attaches a short to a generated case switch" do
    SCShortsCli.parse(["--on"]).color.should eq(SCShortColor::On)
    SCShortsCli.parse(["-c"]).color.should eq(SCShortColor::On)
    SCShortsCli.parse(["--off"]).color.should eq(SCShortColor::Off)
    SCShortsCli.parse(["-C"]).color.should eq(SCShortColor::Off)
  end

  it "lists the case switch in help once it carries a short" do
    SCShortsCli.help.should contain("--on, -c")
  end

  it "leaves a case switch with no short out of help" do
    # A plain `--off` switch is already implied by the flag's own
    # `auto|on|off` placeholder, so only the ones carrying an
    # otherwise-invisible short earn a row.
    rendered = SCShortRoot.help
    rendered.should contain("--on, -c")
    rendered.should_not contain("--off")
  end

  it "routes past a short shortcut to a subcommand" do
    inst = SCShortRoot.dispatch(["-c", "sub"])
    inst.should be_a(SCShortSub)
  end
end

describe "shortcut_flags spelling validation" do
  it "rejects a multi-character single-dash spelling" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadShortLen
        Alpha
        Beta
      end
      Shell::AutoComplete.command BadShortLenCli, name: "b", description: "x" do
        flag choice : BadShortLen = BadShortLen::Alpha, "--choice", "c",
          shortcut_flags: {aliases: {"-ab": :beta}}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("exactly one character after the dash")
  end

  it "rejects a spelling that is a reserved flag name" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadReserved
        Alpha
        Beta
      end
      Shell::AutoComplete.command BadReservedCli, name: "b", description: "x" do
        flag choice : BadReserved = BadReserved::Alpha, "--choice", "c",
          shortcut_flags: {aliases: {"-h": :beta}}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("-h is a reserved flag name")
  end

  it "rejects a short colliding with a declared flag" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadCollide
        Alpha
        Beta
      end
      Shell::AutoComplete.command BadCollideCli, name: "b", description: "x" do
        flag count : Int32 = 1, "--count", "-c", "count"
        flag choice : BadCollide = BadCollide::Alpha, "--choice", "c",
          shortcut_flags: {aliases: {"-c": :beta}}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name -c")
  end

  it "rejects shorts: naming a case that only:/except: excludes" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadShortExcluded
        Alpha
        Beta
      end
      Shell::AutoComplete.command BadShortExcludedCli, name: "b", description: "x" do
        flag choice : BadShortExcluded = BadShortExcluded::Alpha, "--choice", "c",
          shortcut_flags: {except: [:beta], shorts: {beta: "-b"}}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("names a case that only:/except: excludes")
  end

  it "rejects an unknown option in an alias tuple" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadAliasOpt
        Alpha
        Beta
      end
      Shell::AutoComplete.command BadAliasOptCli, name: "b", description: "x" do
        flag choice : BadAliasOpt = BadAliasOpt::Alpha, "--choice", "c",
          shortcut_flags: {aliases: {go: {value: :beta, longg: "--nope"}}}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("unknown shortcut_flags alias option")
  end

  it "rejects an alias tuple with no value:" do
    status, err = compile_fragment <<-FRAGMENT
      enum BadAliasNoValue
        Alpha
        Beta
      end
      Shell::AutoComplete.command BadAliasNoValueCli, name: "b", description: "x" do
        flag choice : BadAliasNoValue = BadAliasNoValue::Alpha, "--choice", "c",
          shortcut_flags: {aliases: {go: {short: "-g"}}}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("needs value: naming the enum case")
  end
end
