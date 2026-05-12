require "../spec_helper"

Shell::AutoComplete.command CompleteWithCli, name: "cwcli", description: "x" do
  flag branch : String?, "--branch", "b", complete_with: :git_branches

  def self.git_branches(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
    %w[main develop feature-x feature-y]
  end
end

describe "complete_with:" do
  it "calls the named method when completing the flag's value" do
    output = IO::Memory.new
    CompleteWithCli.dispatch(["__complete", "2", "cwcli", "--branch", ""], stdout: output)
    lines = output.to_s.lines.map(&.chomp)
    lines.should contain("main")
    lines.should contain("develop")
    lines.should contain("feature-x")
    lines.should contain("feature-y")
  end

  it "filters by prefix (the shell does this; we just emit all candidates)" do
    # The Crystal side emits all; bash does compgen filtering.
    output = IO::Memory.new
    CompleteWithCli.dispatch(["__complete", "2", "cwcli", "--branch", "feat"], stdout: output)
    lines = output.to_s.lines.map(&.chomp)
    lines.should contain("feature-x")
    lines.should contain("feature-y")
    lines.should contain("main")
    lines.should contain("develop")
  end
end
