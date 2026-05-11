require "../spec_helper"

Shell::AutoComplete.command ZshCli, name: "zshcli", description: "x" do
  flag verbose : Bool = false, "--verbose", "-v"
end

describe "Zsh renderer" do
  it "emits a compdef directive" do
    script = ZshCli.completion_script(:zsh)
    script.should contain("compdef")
    script.should contain("zshcli")
  end

  it "calls __complete via the binary" do
    script = ZshCli.completion_script(:zsh)
    script.should contain("__complete")
  end
end
