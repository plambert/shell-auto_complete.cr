require "../spec_helper"
require "uri"
require "log"

# Issue #19: value placeholders (metavars) in help — three input forms plus
# type-derived defaults.

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-ph", ".cr", dir: spec_tmp_dir)
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

enum PHDirection
  Asc
  Desc
end

Shell::AutoComplete.command PlaceholderCli, name: "ph", description: "x" do
  flag port : Int32?, "--port", "PORT", "Server port"
  flag after : String?, "--after TIME", "Ignore entries before TIME"
  flag host : String?, "--host", "Bind host", placeholder: "HOST[:port]"
  flag mapping : String?, "--mapping", "SRC:DST", "Path mapping"
  flag rate : Float64?, "--rate", "Sample rate"
  flag title : String?, "--title", "Title"
  flag site : URI?, "--site", "Site URL"
  flag at : Time?, "--at", "Start time"
  flag pattern : Regex?, "--pattern", "Pattern"
  flag input : File?, "--input", "Input file"
  flag direction : PHDirection?, "--direction", "Sort direction"
  flag level : Log::Severity?, "--level", "Log level"
  flag env : Hash(String, String) = {} of String => String, "--env", "Env entries"
  flag pick : String?, "--pick", "Pick one", choices: %w[red green blue]
  flag ints : Array(Int32) = [] of Int32, "--ints", "Numbers", delimiter: ","
  flag covers : Bool = false, "--covers", "Include covers"
end

private def option_line(rendered : String, flag_name : String) : String
  line = rendered.lines.find(&.lstrip.starts_with?(flag_name))
  line.should_not be_nil
  line.not_nil!
end

describe "value placeholders in help" do
  rendered = PlaceholderCli.help

  it "uses a positional all-caps placeholder" do
    option_line(rendered, "--port").should contain("--port PORT")
    option_line(rendered, "--port").should contain("Server port")
  end

  it "uses a placeholder embedded in the flag string" do
    option_line(rendered, "--after").should contain("--after TIME")
    option_line(rendered, "--after").should contain("Ignore entries before TIME")
    PlaceholderCli.parse(["--after", "x"]).after.should eq("x")
  end

  it "uses the placeholder: named option for shapes the heuristics cannot express" do
    option_line(rendered, "--host").should contain("--host HOST[:port]")
  end

  it "accepts punctuated placeholders like SRC:DST" do
    option_line(rendered, "--mapping").should contain("--mapping SRC:DST")
  end

  it "derives type defaults" do
    option_line(rendered, "--ints").should contain("--ints NUMBER")
    option_line(rendered, "--rate").should contain("--rate FLOAT")
    option_line(rendered, "--title").should contain("--title TEXT")
    option_line(rendered, "--site").should contain("--site URL")
    option_line(rendered, "--at").should contain("--at TIME")
    option_line(rendered, "--pattern").should contain("--pattern REGEX")
    option_line(rendered, "--input").should contain("--input FILE")
    option_line(rendered, "--env").should contain("--env KEY=VALUE")
  end

  it "pipe-joins small enums and choices" do
    option_line(rendered, "--direction").should contain("--direction asc|desc")
    option_line(rendered, "--pick").should contain("--pick red|green|blue")
  end

  it "upcases the type name for large enums" do
    option_line(rendered, "--level").should contain("--level SEVERITY")
  end

  it "gives switches no placeholder" do
    option_line(rendered, "--covers").should match(/--covers\s{2,}Include covers/)
  end
end

describe "placeholder compile guards" do
  it "rejects an unconsumed extra string literal" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command ExtraString, name: "x", description: "x" do
        flag port : Int32?, "--port", "PORT", "Server port", "stray"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("unconsumed extra string literal")
  end

  it "rejects more than one placeholder" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command TwoPlaceholders, name: "x", description: "x" do
        flag port : Int32?, "--port NUM", "PORT", "Server port"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("more than one placeholder")
  end

  it "rejects a placeholder on a switch" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command SwitchPlaceholder, name: "x", description: "x" do
        flag covers : Bool = false, "--covers", "Include covers", placeholder: "X"
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("switch flag covers cannot take a placeholder")
  end
end
