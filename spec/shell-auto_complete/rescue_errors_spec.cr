require "../spec_helper"

# Compile a small example binary and run it to verify the rescue path.
# Each test spawns a subprocess so we can observe the real exit code and stderr
# without the rescue path terminating the spec runner.
private def run_rescue_example(argv : Array(String)) : NamedTuple(stdout: String, stderr: String, status: Process::Status)
  project_root = "#{__DIR__}/../.."
  src = <<-'CR'
  require "./src/shell-auto_complete"

  Shell::AutoComplete.command RescueExample, name: "rescuex", description: "rescue test" do
    flag count : Int32 = 1, "--count", "c", range: 1..10

    def run
      STDOUT.puts "count=#{count}"
    end
  end

  RescueExample.dispatch(ARGV)
  CR
  src_file = File.tempfile("sac-rescue-src", ".cr", dir: project_root)
  bin_file = File.tempfile("sac-rescue-bin", dir: project_root)
  begin
    File.write(src_file.path, src)
    build = Process.run(
      "crystal",
      ["build", src_file.path, "-o", bin_file.path],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close,
    )
    raise "compile failed" unless build.success?
    out_io = IO::Memory.new
    err_io = IO::Memory.new
    status = Process.run(bin_file.path, argv, output: out_io, error: err_io)
    {stdout: out_io.to_s, stderr: err_io.to_s, status: status}
  ensure
    src_file.delete
    File.delete(bin_file.path) if File.exists?(bin_file.path)
  end
end

describe "dispatch rescue_errors (default true)" do
  it "happy path: exits 0 with stdout output" do
    result = run_rescue_example(["--count", "5"])
    result[:status].success?.should be_true
    result[:stdout].should contain("count=5")
    result[:stderr].should be_empty
  end

  it "ParseError (unknown flag) → exits 1, writes to STDERR" do
    result = run_rescue_example(["--bogus"])
    result[:status].success?.should be_false
    result[:status].exit_code.should eq(1)
    result[:stderr].should contain("Error:")
  end

  it "validation failure (out-of-range Int32) → exits 1, writes to STDERR" do
    result = run_rescue_example(["--count", "100"])
    result[:status].success?.should be_false
    result[:status].exit_code.should eq(1)
    result[:stderr].should contain("Error:")
  end
end
