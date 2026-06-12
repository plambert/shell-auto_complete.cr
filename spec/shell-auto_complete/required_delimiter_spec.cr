require "../spec_helper"

# Issue #17: delimiter: is a required, explicit choice on collection flags.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "./src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-delim", ".cr", dir: "#{__DIR__}/../..")
  begin
    File.write(tmp.path, src)
    error_io = IO::Memory.new
    status = Process.run("crystal", ["build", "--no-debug", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: error_io)
    {status, error_io.to_s}
  ensure
    tmp.delete
  end
end

Shell::AutoComplete.command DelimCli, name: "dl", description: "x" do
  flag tags : Array(String) = [] of String, "--tags", "Tags", delimiter: ","
  flag titles : Array(String) = [] of String, "--title", "Titles", delimiter: nil
end

describe "required delimiter:" do
  it "rejects an Array flag without delimiter: at compile time" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command NoDelimArray, name: "x", description: "x" do
        flag tags : Array(String) = [] of String, "--tags", "Tags"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("must state its splitting behavior")
    err.should contain("delimiter:")
  end

  it "rejects a Set flag without delimiter: at compile time" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command NoDelimSet, name: "x", description: "x" do
        flag tags : Set(String) = Set(String).new, "--tags", "Tags"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("must state its splitting behavior")
  end

  it "does not require delimiter: on Hash flags (no splitting happens)" do
    status, _err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command HashNoDelim, name: "x", description: "x" do
        flag env : Hash(String, String) = {} of String => String, "--env", "Env"
      end
      FRAGMENT
    status.success?.should be_true
  end

  it "splits on the declared delimiter" do
    DelimCli.parse(["--tags", "a,b"]).tags.should eq(["a", "b"])
  end

  it "treats each occurrence as one element with delimiter: nil" do
    inst = DelimCli.parse(["--title", "War, and Peace", "--title", "Hello"])
    inst.titles.should eq(["War, and Peace", "Hello"])
  end
end
