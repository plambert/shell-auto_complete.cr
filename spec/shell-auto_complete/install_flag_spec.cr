require "../spec_helper"

Shell::AutoComplete.command InstallCli, name: "icli", description: "x" do
  flag foo : String?, "--foo", "f"
end

Shell::AutoComplete.command CustomInstallCli, name: "ccli", description: "x" do
  shell_completion_flag "--gen-completion"
  flag foo : String?, "--foo", "f"
end

# Simulates a tty stdout for testing the tty branch.
class TtyIO < IO
  property bytes_written = 0

  def read(slice : Bytes)
    0
  end

  def write(slice : Bytes) : Nil
    @bytes_written += slice.size
  end

  def tty?
    true
  end
end

describe "--shell-completion handler" do
  it "writes a completion script to stdout when piped" do
    stdout_buf = IO::Memory.new
    stderr_buf = IO::Memory.new
    result = InstallCli.dispatch(["--shell-completion", "bash"], stdout: stdout_buf, stderr: stderr_buf)
    stdout_buf.to_s.should contain("icli")
    result.should be_nil
  end

  it "writes install example to stderr when stdout is a tty" do
    stdout_tty = TtyIO.new
    stderr_buf = IO::Memory.new
    InstallCli.dispatch(["--shell-completion", "bash"], stdout: stdout_tty, stderr: stderr_buf)
    stderr_buf.to_s.should contain("eval")
    stdout_tty.bytes_written.should eq(0)
  end

  it "writes shell list to stderr when shell name is missing" do
    stdout_buf = IO::Memory.new
    stderr_buf = IO::Memory.new
    InstallCli.dispatch(["--shell-completion"], stdout: stdout_buf, stderr: stderr_buf)
    stderr_buf.to_s.should contain("bash")
    stderr_buf.to_s.should contain("zsh")
    stderr_buf.to_s.should contain("fish")
  end

  it "writes shell list to stderr when shell name is invalid" do
    stdout_buf = IO::Memory.new
    stderr_buf = IO::Memory.new
    InstallCli.dispatch(["--shell-completion", "powershell"], stdout: stdout_buf, stderr: stderr_buf)
    stderr_buf.to_s.should contain("bash")
  end
end

describe "shell_completion_flag macro" do
  it "uses the custom flag name" do
    stdout_buf = IO::Memory.new
    stderr_buf = IO::Memory.new
    CustomInstallCli.dispatch(["--gen-completion", "bash"], stdout: stdout_buf, stderr: stderr_buf)
    stdout_buf.to_s.should contain("ccli")
  end

  it "does NOT intercept --shell-completion when overridden" do
    # With a custom flag name, the default --shell-completion is not intercepted
    # and would be treated as a regular (unknown) flag.
    expect_raises(Shell::AutoComplete::ParseError) do
      CustomInstallCli.dispatch(["--shell-completion", "bash"], rescue_errors: false)
    end
  end
end
