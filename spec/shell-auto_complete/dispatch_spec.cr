require "../spec_helper"

class DispatchCli < Shell::AutoComplete::Command
end

Shell::AutoComplete.command DispatchTestCli, name: "dispatch-cli", description: "x" do
  flag message : String?, "--message", "m"

  @ran = false

  def ran?
    @ran
  end

  def run
    @ran = true
  end
end

describe "Command.dispatch" do
  it "parses argv and invokes #run, returning the populated instance" do
    inst = DispatchTestCli.dispatch(["--message", "hi"])
    inst.message.should eq("hi")
    inst.ran?.should be_true
  end

  it "still raises NotRunnable when subclass does not override #run" do
    expect_raises(Shell::AutoComplete::NotRunnable) do
      DispatchCli.dispatch([] of String)
    end
  end
end
