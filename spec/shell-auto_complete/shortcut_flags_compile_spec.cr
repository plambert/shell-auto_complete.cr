require "../spec_helper"

private def compile_fragment(body : String) : Process::Status
  src = <<-CR
    require "./src/shell-auto_complete"
    #{body}
  CR
  tmp = File.tempfile("sac-sfflags", ".cr", dir: "#{__DIR__}/../..")
  begin
    File.write(tmp.path, src)
    Process.run("crystal", ["build", "--no-codegen", tmp.path],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close)
  ensure
    tmp.delete
  end
end

describe "shortcut_flags compile guard" do
  it "rejects shortcut_flags: true on an @[Flags] enum" do
    status = compile_fragment <<-FRAGMENT
      @[Flags]
      enum BadEnum
        Read
        Write
      end
      Shell::AutoComplete.command BadShortcut, name: "x", description: "x" do
        flag perms : BadEnum = BadEnum::None, "--perms", "p", shortcut_flags: true
      end
    FRAGMENT
    status.success?.should be_false
  end

  it "allows shortcut_flags: true on a plain enum" do
    status = compile_fragment <<-FRAGMENT
      enum GoodEnum
        Alpha
        Beta
      end
      Shell::AutoComplete.command GoodShortcut, name: "x", description: "x" do
        flag choice : GoodEnum = GoodEnum::Alpha, "--choice", shortcut_flags: true
      end
    FRAGMENT
    status.success?.should be_true
  end
end
