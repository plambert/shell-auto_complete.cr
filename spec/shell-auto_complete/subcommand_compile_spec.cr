require "../spec_helper"

private def compile_fragment(body : String) : Process::Status
  src = <<-CR
    require "./src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-subcmd", ".cr", dir: "#{__DIR__}/../..")
  begin
    File.write(tmp.path, src)
    Process.run("crystal", ["build", "--no-debug", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close)
  ensure
    tmp.delete
  end
end

describe "subcommand compile guards" do
  it "rejects a command with both subcommand and positional" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadLeaf, name: "leaf", description: "x" do
        def run
        end
      end
      Shell::AutoComplete.command BadMix, name: "x", description: "x" do
        subcommand BadLeaf
        positional foo : String, "the foo"
      end
      FRAGMENT
    status.success?.should be_false
  end
end
