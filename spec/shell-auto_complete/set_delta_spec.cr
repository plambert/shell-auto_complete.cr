require "../spec_helper"

alias SetDelta = Shell::AutoComplete::Types::SetDelta

# A variadic SetDelta positional accepts `+name` / `-name` / bare `name` tokens
# and binds them into a Hash(String, Bool).
Shell::AutoComplete.command FeatToggle, name: "feat", description: "toggle features" do
  flag verbose : Bool = false, "--verbose", "-v"
  positionals changes : Shell::AutoComplete::Types::SetDelta, "features to toggle"

  def run
  end
end

# With min/max bounds.
Shell::AutoComplete.command FeatBounded, name: "featb", description: "x" do
  positionals changes : Shell::AutoComplete::Types::SetDelta, "changes", min: 1, max: 2

  def run
  end
end

describe "Shell::AutoComplete::Types::SetDelta" do
  describe ".__arg_transform" do
    it "maps +name to true" do
      SetDelta.__arg_transform("+foo").should eq({"foo" => true})
    end

    it "maps -name to false" do
      SetDelta.__arg_transform("-bar").should eq({"bar" => false})
    end

    it "maps a bare name to true" do
      SetDelta.__arg_transform("baz").should eq({"baz" => true})
    end

    it "raises on a bare +/- with no name" do
      expect_raises(ArgumentError, /empty set-delta token/) { SetDelta.__arg_transform("+") }
      expect_raises(ArgumentError, /empty set-delta token/) { SetDelta.__arg_transform("-") }
      expect_raises(ArgumentError, /empty set-delta token/) { SetDelta.__arg_transform("") }
    end
  end

  describe ".apply" do
    it "adds keys mapped to true and removes keys mapped to false" do
      set = Set{"keep", "drop"}
      result = SetDelta.apply(set, {"add" => true, "drop" => false})
      result.should eq(Set{"keep", "add"})
    end

    it "mutates and returns the same set" do
      set = Set(String).new
      SetDelta.apply(set, {"x" => true}).should be(set)
      set.should eq(Set{"x"})
    end

    it "ignores a remove of a key not present" do
      SetDelta.apply(Set{"a"}, {"b" => false}).should eq(Set{"a"})
    end
  end
end

describe "SetDelta positionals" do
  it "binds +name/-name tokens into a Hash(String, Bool)" do
    inst = FeatToggle.parse(["+foo", "-bar"])
    inst.changes.should eq({"foo" => true, "bar" => false})
  end

  it "treats a bare token as an add (true)" do
    FeatToggle.parse(["baz"]).changes.should eq({"baz" => true})
  end

  it "accepts a single -name token without treating it as an unknown flag" do
    FeatToggle.parse(["-alpha"]).changes.should eq({"alpha" => false})
  end

  it "binds an empty hash when no tokens are given" do
    FeatToggle.parse([] of String).changes.empty?.should be_true
  end

  it "still parses real flags interspersed with delta tokens" do
    inst = FeatToggle.parse(["+foo", "--verbose", "-bar"])
    inst.verbose.should be_true
    inst.changes.should eq({"foo" => true, "bar" => false})
  end

  it "lets a known short flag take precedence over a dash token" do
    inst = FeatToggle.parse(["-v", "-x"])
    inst.verbose.should be_true
    inst.changes.should eq({"x" => false})
  end

  it "treats everything after -- as delta tokens" do
    inst = FeatToggle.parse(["--", "-v", "+w"])
    inst.verbose.should be_false
    inst.changes.should eq({"v" => false, "w" => true})
  end

  it "lets the last token win for a repeated key" do
    FeatToggle.parse(["+foo", "-foo"]).changes.should eq({"foo" => false})
  end

  it "raises on a bare +/- with no name" do
    expect_raises(ArgumentError, /empty set-delta token/) { FeatToggle.parse(["+"]) }
  end

  it "enforces min" do
    expect_raises(Shell::AutoComplete::ParseError) { FeatBounded.parse([] of String) }
  end

  it "enforces max (distinct keys)" do
    expect_raises(Shell::AutoComplete::ParseError) { FeatBounded.parse(["+a", "+b", "+c"]) }
  end

  it "round-trips: parse a delta and apply it to a set" do
    delta = FeatToggle.parse(["+dark-mode", "-telemetry", "beta"]).changes
    SetDelta.apply(Set{"telemetry", "legacy"}, delta).should eq(Set{"legacy", "dark-mode", "beta"})
  end
end

describe "Hash positionals are rejected at compile time" do
  it "points the user at SetDelta" do
    src = <<-CR
      require "./src/shell-auto_complete"
      Shell::AutoComplete.command BadHashPos, name: "x", description: "x" do
        positionals items : Hash(String, Bool), "items"
      end
      CR
    tmp = File.tempfile("sac-hashpos", ".cr", dir: File.expand_path("#{__DIR__}/../.."))
    begin
      File.write(tmp.path, src)
      result = Process.run("crystal",
        ["build", "--no-codegen", tmp.path],
        output: Process::Redirect::Close,
        error: Process::Redirect::Close)
      result.success?.should be_false
    ensure
      tmp.delete
    end
  end
end
