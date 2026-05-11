require "../spec_helper"

Shell::AutoComplete.command BashCli, name: "bashcli", description: "x" do
  flag verbose : Bool = false, "--verbose", "-v"
end

describe "Bash renderer" do
  it "emits a complete -F directive" do
    script = BashCli.completion_script(:bash)
    script.should contain("complete -F")
    script.should contain("bashcli")
  end

  it "emits a function that calls __complete" do
    script = BashCli.completion_script(:bash)
    script.should contain("__complete")
  end
end
