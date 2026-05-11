require "../../spec_helper"

Shell::AutoComplete.command NonNegCli, name: "nn", description: "x" do
  flag verbose : Bool = false, "--verbose", "-v", "verbose", negatable: false
end

Shell::AutoComplete.command NegCli, name: "n", description: "x" do
  flag verbose : Bool = false, "--verbose", "verbose" # negatable defaults to true
end

describe "negatable: false" do
  it "still accepts --verbose" do
    NonNegCli.parse(["--verbose"]).verbose.should be_true
  end

  it "rejects --no-verbose when negatable: false" do
    expect_raises(Shell::AutoComplete::ParseError) do
      NonNegCli.parse(["--no-verbose"])
    end
  end

  it "accepts --no-verbose by default" do
    NegCli.parse(["--no-verbose"]).verbose.should be_false
  end
end
