require "../spec_helper"

Shell::AutoComplete.command MatchCli, name: "m", description: "x" do
  flag name : String?, "--name", "n", matches: /\A[a-z][a-z0-9-]*\z/
end

Shell::AutoComplete.command ChoicesCli, name: "c", description: "x" do
  flag color : String?, "--color", "c", choices: %w[red green blue]
end

describe "String matches:" do
  it "accepts matching values" do
    MatchCli.parse(["--name", "abc-123"]).name.should eq("abc-123")
  end

  it "rejects non-matching values" do
    expect_raises(Shell::AutoComplete::ParseError) do
      MatchCli.parse(["--name", "Abc"])
    end
  end
end

describe "String choices:" do
  it "accepts listed values" do
    ChoicesCli.parse(["--color", "red"]).color.should eq("red")
  end

  it "rejects unlisted values" do
    expect_raises(Shell::AutoComplete::ParseError, /not one of/) do
      ChoicesCli.parse(["--color", "purple"])
    end
  end
end
