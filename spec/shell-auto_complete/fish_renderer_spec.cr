require "../spec_helper"

Shell::AutoComplete.command FishCli, name: "fishcli", description: "x" do
  flag verbose : Bool = false, "--verbose", "-v"
end

describe "Fish renderer" do
  it "emits a 'complete -c' directive" do
    script = FishCli.completion_script(:fish)
    script.should contain("complete -c")
    script.should contain("fishcli")
  end

  it "calls __complete via the binary" do
    script = FishCli.completion_script(:fish)
    script.should contain("__complete")
  end
end
