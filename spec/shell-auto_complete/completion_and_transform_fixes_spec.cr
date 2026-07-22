require "../spec_helper"

# Regressions for five defects found while migrating consumer CLIs to 2.4.0.

CF_COLUMNS = %w[id name size]

Shell::AutoComplete.command CfLeaf, name: "leaf", description: "leaf" do
  flag width : Int32?, "--width", "width"

  def run
  end
end

Shell::AutoComplete.command CfMid, name: "mid", description: "mid", aliases: ["m2"] do
  subcommand CfLeaf

  def run
  end
end

Shell::AutoComplete.command CfRoot, name: "cfroot", description: "root" do
  flag verbose : Bool = false, "--verbose", "-v", "verbose"
  flag mode : String?, "--mode", "mode", choices: %w[alpha beta]
  subcommand CfMid

  def run
  end
end

Shell::AutoComplete.command CfChoices, name: "cfchoices", description: "choices" do
  # choices: as a constant reference rather than an array literal.
  flag scalar : String?, "--scalar", "const choices", choices: CF_COLUMNS
  flag listed : Array(String) = [] of String, "--listed", "collection choices",
    delimiter: ",", choices: CF_COLUMNS

  def run
  end
end

Shell::AutoComplete.command CfUri, name: "cfuri", description: "uri" do
  flag endpoint : URI?, "--endpoint", "endpoint"

  def run
  end
end

Shell::AutoComplete.command CfVariadic, name: "cfvariadic", description: "variadic" do
  positional first : String, "scalar", transform_with: :shout
  positionals rest : Array(String), "variadic", transform_with: :shout, validate_with: :short?

  def self.shout(value : String) : String
    raise ArgumentError.new("no digits allowed") if value =~ /\d/
    value.upcase
  end

  def self.short?(value : String) : Bool | String
    value.size <= 6 || "#{value} is too long"
  end

  def run
  end
end

private def cf_complete(klass, argv)
  output = IO::Memory.new
  klass.dispatch(argv, stdout: output)
  output.to_s.lines.map(&.strip)
end

describe "subcommand completion past preceding flags" do
  it "offers subcommands when no flag precedes the cursor" do
    cf_complete(CfRoot, ["__complete", "1", "cfroot", "m"]).should eq(["mid", "m2"])
  end

  it "still offers subcommands when a switch precedes the cursor" do
    cf_complete(CfRoot, ["__complete", "2", "cfroot", "-v", "m"]).should eq(["mid", "m2"])
  end

  it "still offers subcommands after a flag and its value" do
    cf_complete(CfRoot, ["__complete", "3", "cfroot", "--mode", "alpha", "m"]).should eq(["mid", "m2"])
  end

  it "descends into a subcommand reached past a flag" do
    cf_complete(CfRoot, ["__complete", "3", "cfroot", "-v", "mid", ""]).should contain("leaf")
  end

  it "descends through an alias reached past a flag" do
    cf_complete(CfRoot, ["__complete", "3", "cfroot", "-v", "m2", ""]).should contain("leaf")
  end

  it "does not offer subcommand names in a flag's value position" do
    candidates = cf_complete(CfRoot, ["__complete", "2", "cfroot", "--mode", ""])
    candidates.should eq(["alpha", "beta"])
    candidates.should_not contain("mid")
  end

  it "does not offer a subcommand once one has been consumed" do
    cf_complete(CfRoot, ["__complete", "3", "cfroot", "mid", "leaf", ""]).should_not contain("mid")
  end
end

describe "choices: given a constant reference" do
  it "completes a scalar flag's choices" do
    cf_complete(CfChoices, ["__complete", "2", "cfchoices", "--scalar", ""]).should eq(CF_COLUMNS)
  end

  it "prefix-filters a scalar flag's choices" do
    cf_complete(CfChoices, ["__complete", "2", "cfchoices", "--scalar", "s"]).should eq(["size"])
  end

  it "still validates against the constant's values" do
    expect_raises(Shell::AutoComplete::ParseError, /--scalar: bogus is not one of/) do
      CfChoices.parse(["--scalar", "bogus"])
    end
  end
end

describe "choices: on a delimited collection flag" do
  it "completes whole values when no delimiter is present" do
    cf_complete(CfChoices, ["__complete", "2", "cfchoices", "--listed", ""]).should eq(CF_COLUMNS)
  end

  it "completes the element after the last delimiter, keeping the prefix" do
    cf_complete(CfChoices, ["__complete", "2", "cfchoices", "--listed", "id,"])
      .should eq(["id,name", "id,size"])
  end

  it "does not re-offer an element already present" do
    cf_complete(CfChoices, ["__complete", "2", "cfchoices", "--listed", "id,name,"])
      .should eq(["id,name,size"])
  end

  it "prefix-filters the trailing element" do
    cf_complete(CfChoices, ["__complete", "2", "cfchoices", "--listed", "id,s"])
      .should eq(["id,size"])
  end
end

describe "URI transform" do
  it "converts URI::Error into a parse error naming the flag" do
    expect_raises(Shell::AutoComplete::ParseError, /--endpoint: /) do
      CfUri.parse(["--endpoint", "http://example.com:notaport"])
    end
  end

  it "still accepts a valid URI" do
    CfUri.parse(["--endpoint", "https://example.com/x"]).endpoint.should eq(URI.parse("https://example.com/x"))
  end
end

describe "variadic positional transform_with:/validate_with:" do
  it "applies the transform to every element, not just the scalar" do
    inst = CfVariadic.parse(["aa", "bb", "cc"])
    inst.first.should eq("AA")
    inst.rest.should eq(["BB", "CC"])
  end

  it "converts an ArgumentError from the transform into a parse error naming the positional" do
    expect_raises(Shell::AutoComplete::ParseError, /rest: no digits allowed/) do
      CfVariadic.parse(["aa", "b2"])
    end
  end

  it "runs the validator on every element" do
    expect_raises(Shell::AutoComplete::ParseError, /rest: TOOLONGVALUE is too long/) do
      CfVariadic.parse(["aa", "toolongvalue"])
    end
  end

  it "accepts elements that satisfy the validator" do
    CfVariadic.parse(["aa", "ok", "fine"]).rest.should eq(["OK", "FINE"])
  end
end
