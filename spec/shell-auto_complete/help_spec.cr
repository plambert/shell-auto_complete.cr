require "../spec_helper"

Shell::AutoComplete.command HelpCli, name: "helpcli", description: "demo command" do
  flag message : String?, "--message", "-m", "the message"
  flag count : Int32 = 1, "--count", "iterations"
end

describe "Command.help" do
  it "renders usage" do
    HelpCli.help.should contain("Usage: helpcli")
  end

  it "includes the description" do
    HelpCli.help.should contain("demo command")
  end

  it "lists each flag's canonical and description" do
    text = HelpCli.help
    text.should contain("--message")
    text.should contain("the message")
    text.should contain("--count")
    text.should contain("iterations")
  end

  it "includes short flag in options section" do
    HelpCli.help.should contain("-m")
  end
end

describe "dispatch --help" do
  it "prints help to stdout and returns nil" do
    io = IO::Memory.new
    result = HelpCli.dispatch(["--help"], stdout: io)
    result.should be_nil
    io.to_s.should contain("Usage: helpcli")
  end

  it "responds to -h the same way" do
    io = IO::Memory.new
    HelpCli.dispatch(["-h"], stdout: io)
    io.to_s.should contain("Usage: helpcli")
  end
end
