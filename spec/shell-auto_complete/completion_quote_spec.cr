require "../spec_helper"

Shell::AutoComplete.command QSpace, name: "my tool", description: "x" do
  def run
  end
end

Shell::AutoComplete.command QRedir, name: "tool>oops", description: "x" do
  def run
  end
end

Shell::AutoComplete.command QInject, name: "t;echo pwned $(id)`x`", description: "x" do
  def run
  end
end

Shell::AutoComplete.command QTick, name: "a'b'c", description: "x" do
  def run
  end
end

Shell::AutoComplete.command QClean, name: "tool", description: "x" do
  def run
  end
end

describe "Completion::Quote" do
  it "single-quotes a plain value for POSIX shells" do
    Shell::AutoComplete::Completion::Quote.posix("tool").should eq("'tool'")
  end

  it "escapes embedded single quotes with '\\'' for POSIX shells" do
    Shell::AutoComplete::Completion::Quote.posix("a'b").should eq("'a'\\''b'")
  end

  it "escapes backslashes and single quotes for fish" do
    Shell::AutoComplete::Completion::Quote.fish("a'b\\c").should eq("'a\\'b\\\\c'")
  end
end

describe "completion script quoting" do
  {% for shell in [:bash, :zsh, :fish] %}
    it "quotes a command name with a space ({{ shell.id }})" do
      script = QSpace.completion_script({{ shell }})
      script.should contain("'my tool'")
    end

    it "quotes a command name containing a redirection ({{ shell.id }})" do
      script = QRedir.completion_script({{ shell }})
      # The bare, unquoted `tool>oops` never appears — it is always inside
      # single quotes, so the shell cannot treat `>` as a redirection.
      script.should_not match(/[^'>]tool>oops/)
      script.should contain("'tool>oops'")
    end
  {% end %}

  it "neutralizes shell metacharacters so sourcing runs nothing (bash)" do
    script = QInject.completion_script(:bash)
    # The dangerous substring only ever appears single-quoted.
    script.should contain("'t;echo pwned $(id)`x`'")
    script.should_not contain("$(id)\n")
  end

  it "escapes an embedded single quote in the command name (bash)" do
    QTick.completion_script(:bash).should contain("'a'\\''b'\\''c'")
  end
end

describe "completion script executable override" do
  it "uses the given executable in the callback, quoted, keeping the name for registration (bash)" do
    script = QClean.completion_script(:bash, executable: "/opt/my build/bin/tool")
    script.should contain("out=$('/opt/my build/bin/tool' __complete")
    script.should contain("complete -F _tool 'tool'")
  end

  it "does the same for zsh" do
    script = QClean.completion_script(:zsh, executable: "/opt/bin/tool")
    script.should contain("$('/opt/bin/tool' \"__complete\"")
    script.should contain("compdef _tool 'tool'")
  end

  it "does the same for fish" do
    script = QClean.completion_script(:fish, executable: "/opt/bin/tool")
    script.should contain("('/opt/bin/tool' __complete")
    script.should contain("complete -c 'tool'")
  end

  it "defaults the callback to the command name when no executable is given" do
    QClean.completion_script(:bash).should contain("out=$('tool' __complete")
  end
end

describe "--shell-completion --absolute" do
  it "bakes the running binary's absolute path into the callback, keeping the name registered" do
    io = IO::Memory.new
    QClean.dispatch(["--shell-completion", "bash", "--absolute"], stdout: io)
    callback = io.to_s.lines.find!(&.includes?("__complete"))
    # An absolute, single-quoted path, not the bare command name.
    callback.should match(/out=\$\('\/.+' __complete/)
    io.to_s.should contain("complete -F _tool 'tool'")
  end

  it "accepts the -a short form" do
    io = IO::Memory.new
    QClean.dispatch(["--shell-completion", "bash", "-a"], stdout: io)
    io.to_s.lines.find!(&.includes?("__complete")).should match(/out=\$\('\//)
  end

  it "keeps the bare command name without the option" do
    io = IO::Memory.new
    QClean.dispatch(["--shell-completion", "bash"], stdout: io)
    io.to_s.should contain("out=$('tool' __complete")
  end

  it "rejects an unknown trailing option" do
    err = IO::Memory.new
    QClean.dispatch(["--shell-completion", "bash", "--bogus"], stdout: IO::Memory.new, stderr: err)
    err.to_s.should contain("Unknown option: --bogus")
  end
end
