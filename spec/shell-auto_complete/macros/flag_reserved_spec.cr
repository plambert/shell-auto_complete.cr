require "../../spec_helper"

# Compile a Crystal fragment that requires the shard.  Returns the process
# status so the caller can assert success or failure.
#
# Temp files are written into the project root so that the relative require
# `"./src/shell-auto_complete"` resolves correctly (Crystal resolves relative
# requires relative to the source file, not the working directory).
private def compile_fragment(body : String) : Process::Status
  src = <<-CR
    require "./src/shell-auto_complete"
    #{body}
    CR
  project_root = File.expand_path("#{__DIR__}/../../..")
  tmp = File.tempfile("sac-flag-reserved", ".cr", dir: project_root)
  begin
    File.write(tmp.path, src)
    Process.run("crystal", ["build", "--no-debug", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close)
  ensure
    tmp.delete
  end
end

describe "flag macro reserved names" do
  it "rejects --help as a long flag" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadHelp, name: "x", description: "x" do
        flag foo : String?, "--help", "desc"
      end
      FRAGMENT
    status.success?.should be_false
  end

  it "rejects -h as a short flag" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadH, name: "x", description: "x" do
        flag foo : String?, "--foo", "-h", "desc"
      end
      FRAGMENT
    status.success?.should be_false
  end

  it "accepts --help-me (similar but not reserved)" do
    status = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command OkHelpMe, name: "x", description: "x" do
        flag foo : String?, "--help-me", "desc"
      end
      FRAGMENT
    status.success?.should be_true
  end
end
