require "../spec_helper"

# `bare_number:` — a token that is the flag and its value at once, the
# `head -20` / `less +50` shape.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-barenum", ".cr", dir: spec_tmp_dir)
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

Shell::AutoComplete.command BareHead, name: "bhead", description: "x" do
  flag lines : Int32 = 10, "--lines N", "Lines to show", bare_number: true
  positionals files : Array(String) = [] of String, "Files"
end

Shell::AutoComplete.command BareLess, name: "bless", description: "x" do
  flag lines : Int32 = 10, "--lines N", "Lines to show", bare_number: {sign: :minus}
  flag start : Int32 = 1, "--start N", "Start line", bare_number: {sign: :plus}
  positionals files : Array(String) = [] of String, "Files"
end

Shell::AutoComplete.command BareSigned, name: "bsigned", description: "x" do
  flag offset : Int32 = 0, "--offset N", "Offset", bare_number: {sign: :both, keep_sign: true}
end

Shell::AutoComplete.command BareSuffix, name: "bsuffix", description: "x" do
  flag size : String = "0", "--size N", "Size", bare_number: {suffix: true}
end

Shell::AutoComplete.command BarePattern, name: "bpattern", description: "x" do
  flag width : Int32 = 80, "--width N", "Width",
    bare_number: {pattern: /\A-w(\d+)\z/, label: "-wNUM", description: "Set the width"}
end

Shell::AutoComplete.command BareRoot, name: "broot", description: "root" do
  flag lines : Int32 = 10, "--lines N", "Lines to show", bare_number: {sign: :both}
end

Shell::AutoComplete.command BareSub, name: "sub", description: "child", parent: BareRoot do
  def run
  end
end

class BareRoot
  subcommand BareSub
end

describe "bare_number: true" do
  it "binds the number to the flag" do
    BareHead.parse(["-20"]).lines.should eq(20)
  end

  it "shares the flag's value stream, last-wins" do
    BareHead.parse(["-20", "--lines", "5"]).lines.should eq(5)
    BareHead.parse(["--lines", "5", "-20"]).lines.should eq(20)
    BareHead.parse(["-20", "-5"]).lines.should eq(5)
  end

  it "leaves the default alone when absent" do
    BareHead.parse(["a.txt"]).lines.should eq(10)
  end

  it "counts toward flag_given?" do
    BareHead.parse(["-20"]).flag_given?(:lines).should be_true
    BareHead.parse(["a.txt"]).flag_given?(:lines).should be_false
  end

  it "records the token as typed and the value it yielded" do
    BareHead.parse(["-20"]).parsed_occurrences.should eq([{"-20", "20"}])
  end

  it "runs the flag's own transform and validation" do
    expect_raises(Shell::AutoComplete::ParseError, /--lines/) do
      BareHead.parse(["-99999999999999999999"])
    end
  end

  it "does not disturb the positionals around it" do
    inst = BareHead.parse(["a.txt", "-20", "b.txt"])
    inst.lines.should eq(20)
    inst.files.should eq(["a.txt", "b.txt"])
  end

  it "is still a positional after --" do
    BareHead.parse(["--", "-20"]).files.should eq(["-20"])
  end

  it "claims only the minus sign, leaving +20 a positional" do
    inst = BareHead.parse(["+20"])
    inst.files.should eq(["+20"])
    inst.lines.should eq(10)
  end

  it "never shadows a declared flag" do
    BareHead.parse(["--lines", "7"]).lines.should eq(7)
  end
end

describe "bare_number: opposite signs on two flags" do
  it "routes each sign to its own flag" do
    inst = BareLess.parse(["-20", "+50"])
    inst.lines.should eq(20)
    inst.start.should eq(50)
  end

  it "keeps flag_given? separate" do
    inst = BareLess.parse(["+50"])
    inst.flag_given?(:start).should be_true
    inst.flag_given?(:lines).should be_false
  end
end

describe "bare_number keep_sign:" do
  it "hands the sign to the flag with the digits" do
    BareSigned.parse(["-20"]).offset.should eq(-20)
    BareSigned.parse(["+20"]).offset.should eq(20)
  end
end

describe "bare_number suffix:" do
  it "accepts a unit after the digits" do
    BareSuffix.parse(["-123M"]).size.should eq("123M")
    BareSuffix.parse(["-4"]).size.should eq("4")
  end
end

describe "bare_number pattern:" do
  it "matches the given shape and uses capture group 1" do
    BarePattern.parse(["-w120"]).width.should eq(120)
  end

  it "does not match a plain number" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: -120/) do
      BarePattern.parse(["-120"])
    end
  end

  it "uses the given label and description in help" do
    rendered = BarePattern.help
    rendered.should contain("-wNUM")
    rendered.should contain("Set the width")
  end
end

describe "bare_number help" do
  it "lists the shape indented under the flag" do
    rendered = BareHead.help
    rendered.should contain("--lines N")
    rendered.should contain("      -NUM")
    rendered.should contain("Same as --lines with that number")
  end

  it "labels the sign it accepts" do
    BareLess.help.should contain("+NUM")
    BareSigned.help.should contain("-NUM|+NUM")
  end
end

describe "bare_number completion" do
  it "offers no candidate for a bare number" do
    BareHead.completion_candidates(["bhead", "-"], 1, "-", "bhead").should_not contain("-NUM")
  end

  it "still offers the long form" do
    BareHead.completion_candidates(["bhead", "--li"], 1, "--li", "bhead").should contain("--lines")
  end

  it "does not count a bare number as a positional slot" do
    # `+50` is not flag-shaped, so without bare-number awareness it would
    # shift the slot the cursor sits on.
    BareLess.completion_candidates(["bless", "+50", ""], 2, "", "bless").should_not contain("+50")
  end
end

describe "bare_number routing" do
  it "walks past a bare number to find the subcommand word" do
    BareRoot.dispatch(["-20", "sub"]).should be_a(BareSub)
    BareRoot.dispatch(["+20", "sub"]).should be_a(BareSub)
  end
end

describe "bare_number validation" do
  it "rejects a switch flag" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadBareSwitch, name: "b", description: "x" do
        flag verbose : Bool = false, "--verbose", "v", bare_number: true
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("not valid on a switch flag")
  end

  it "rejects a collection flag" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadBareArray, name: "b", description: "x" do
        flag nums : Array(Int32) = [] of Int32, "--nums", "n", delimiter: nil, bare_number: true
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("only valid on a scalar flag")
  end

  it "rejects two flags claiming the same sign" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadBareDup, name: "b", description: "x" do
        flag lines : Int32 = 1, "--lines", "l", bare_number: true
        flag count : Int32 = 1, "--count", "c", bare_number: true
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name -<number>")
  end

  it "rejects an overlapping :both against a :minus" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadBareOverlap, name: "b", description: "x" do
        flag lines : Int32 = 1, "--lines", "l", bare_number: {sign: :minus}
        flag count : Int32 = 1, "--count", "c", bare_number: {sign: :both}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name -<number>")
  end

  it "allows opposite signs on two flags" do
    status, _ = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command OkBareOpposite, name: "b", description: "x" do
        flag lines : Int32 = 1, "--lines", "l", bare_number: {sign: :minus}
        flag start : Int32 = 1, "--start", "s", bare_number: {sign: :plus}
      end
      FRAGMENT
    status.success?.should be_true
  end

  it "rejects an unknown sign" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadBareSign, name: "b", description: "x" do
        flag lines : Int32 = 1, "--lines", "l", bare_number: {sign: :sideways}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("must be :minus, :plus or :both")
  end

  it "rejects pattern: without label:" do
    status, err = compile_fragment <<-'FRAGMENT'
      Shell::AutoComplete.command BadBareNoLabel, name: "b", description: "x" do
        flag lines : Int32 = 1, "--lines", "l", bare_number: {pattern: /\A-(\d+)\z/}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("needs label:")
  end

  it "rejects pattern: alongside sign:" do
    status, err = compile_fragment <<-'FRAGMENT'
      Shell::AutoComplete.command BadBareBoth, name: "b", description: "x" do
        flag lines : Int32 = 1, "--lines", "l",
          bare_number: {pattern: /\A-(\d+)\z/, label: "-N", sign: :plus}
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("has no effect")
  end

  it "rejects a + sign alongside a SetDelta positional" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadBareSetDelta, name: "b", description: "x" do
        flag lines : Int32 = 1, "--lines", "l", bare_number: {sign: :both}
        positionals changes : Shell::AutoComplete::Types::SetDelta, "toggles"
      end
      BadBareSetDelta.parse([] of String)
      FRAGMENT
    status.success?.should be_false
    err.should contain("is ambiguous")
  end
end
