require "../spec_helper"
require "file_utils"

# The generated bash function runs under bash itself here.
{% skip_file if flag?(:win32) %}

Shell::AutoComplete.command BashQuoteCli, name: "bqcli", description: "x" do
  flag album : String?, "--album"

  def run
  end
end

# Runs the generated completion function in a non-interactive bash with the
# given COMP_WORDS, against a stub `__complete` that prints *candidates* and
# records the words it was called with. Returns COMPREPLY and those words.
private def bash_complete(candidates : Array(String), comp_words : Array(String)) : {Array(String), Array(String)}
  dir = File.tempname("sac-bashq")
  Dir.mkdir_p(dir)
  stub = File.join(dir, "stub")
  seen = File.join(dir, "seen")
  File.write(stub, String.build do |io|
    io << "#!/bin/sh\n"
    io << "printf '%s\\n' \"$@\" > " << Shell::AutoComplete::Completion::Quote.posix(seen) << "\n"
    candidates.each { |c| io << "printf '%s\\n' " << Shell::AutoComplete::Completion::Quote.posix(c) << "\n" }
  end)
  File.chmod(stub, 0o755)
  script = File.join(dir, "complete.bash")
  File.write(script, BashQuoteCli.completion_script(:bash, executable: stub))
  driver = <<-SH
    source #{Shell::AutoComplete::Completion::Quote.posix(script)}
    COMP_WORDS=(#{comp_words.map { |w| Shell::AutoComplete::Completion::Quote.posix(w) }.join(' ')})
    COMP_CWORD=#{comp_words.size - 1}
    _bqcli
    printf '%s\\n' "${COMPREPLY[@]}"
    SH
  output = IO::Memory.new
  Process.run("bash", ["-c", driver], output: output, error: Process::Redirect::Inherit)
  seen_words = File.exists?(seen) ? File.read_lines(seen) : [] of String
  {output.to_s.lines, seen_words}
ensure
  FileUtils.rm_rf(dir) if dir
end

private CANDIDATES = ["Lac d'Annecy", "Lac $HOME", "Lac \"q\"", "Lac back\\slash", "plain"]

describe "bash completion quoting" do
  it "escapes an unquoted candidate with printf %q and filters by prefix" do
    reply, _ = bash_complete(CANDIDATES, ["bqcli", "--album", "Lac"])
    reply.should eq(["Lac\\ d\\'Annecy", "Lac\\ \\$HOME", "Lac\\ \\\"q\\\"", "Lac\\ back\\\\slash"])
  end

  it "dequotes a backslash-escaped partial word before matching" do
    reply, seen = bash_complete(CANDIDATES, ["bqcli", "--album", "Lac\\ d"])
    reply.should eq(["Lac\\ d\\'Annecy"])
    seen.last.should eq("Lac d")
  end

  it "escapes for double quotes when the word opened with one" do
    reply, seen = bash_complete(CANDIDATES, ["bqcli", "--album", "\"Lac"])
    reply.should eq(["Lac d'Annecy", "Lac \\$HOME", "Lac \\\"q\\\"", "Lac back\\\\slash"])
    seen.last.should eq("Lac")
  end

  it "escapes for single quotes when the word opened with one" do
    reply, seen = bash_complete(CANDIDATES, ["bqcli", "--album", "'Lac d"])
    reply.should eq(["Lac d'\\''Annecy"])
    seen.last.should eq("Lac d")
  end

  it "passes a plain word through unchanged" do
    reply, seen = bash_complete(CANDIDATES, ["bqcli", "--album", "pl"])
    reply.should eq(["plain"])
    seen.should eq(["__complete", "2", "bqcli", "--album", "pl"])
  end
end
