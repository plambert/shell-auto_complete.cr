require "../../spec_helper"

private def compile_fragment(body : String) : Process::Status
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-rscompletion", ".cr", dir: spec_tmp_dir)
  begin
    File.write(tmp.path, src)
    Process.run("crystal", ["build", "--no-debug", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close)
  ensure
    tmp.delete
  end
end

describe "configurable reserved shell-completion flag" do
  it "rejects user declaring the default --shell-completion as a flag" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadDefault, name: "x", description: "x" do
        flag x : String?, "--shell-completion", "x"
      end
      FRAGMENT
    status.success?.should be_false
  end

  it "rejects user declaring a custom shell_completion_flag as a flag" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadCustom, name: "x", description: "x" do
        shell_completion_flag "--gen-completion"
        flag x : String?, "--gen-completion", "x"
      end
      FRAGMENT
    status.success?.should be_false
  end

  it "allows --shell-completion when a custom flag name is set" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command OkOverride, name: "x", description: "x" do
        shell_completion_flag "--gen-completion"
        flag x : String?, "--shell-completion", "x"
      end
      FRAGMENT
    status.success?.should be_true
  end
end
