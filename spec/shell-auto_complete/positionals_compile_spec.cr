require "../spec_helper"

private def compile_fragment(body : String) : Process::Status
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-positionals", ".cr", dir: spec_tmp_dir)
  begin
    File.write(tmp.path, src)
    Process.run("crystal", ["build", "--no-debug", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close)
  ensure
    tmp.delete
  end
end

describe "positionals compile guards" do
  it "rejects multiple positionals declarations in one command" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadDouble, name: "x", description: "x" do
        positionals a : Array(String), "a"
        positionals b : Array(String), "b"
      end
      FRAGMENT
    status.success?.should be_false
  end
end
