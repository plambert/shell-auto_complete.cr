require "../spec_helper"

# Issue #15: ordered_flag_group — flag groups whose cross-flag order is
# semantic (rsync/tar-style --include/--exclude rule lists).

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-ofg", ".cr", dir: spec_tmp_dir)
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

Shell::AutoComplete.command FilterCli, name: "filt", description: "x" do
  property rules : Array({String, String}) = [] of {String, String}
  property limits : Array(String) = [] of String

  flag verbose : Bool = false, "--verbose", "Verbose"

  ordered_flag_group "Filter rules (applied in command-line order)",
    {"--include" => "PATTERN: include matching files",
     "--exclude" => "PATTERN: exclude matching files"} do |key, value|
    raise ArgumentError.new("empty pattern") if value.empty?
    @rules << {key, value}
  end

  ordered_flag_group "Limits",
    {"--max-size" => "SIZE: maximum size"} do |_key, value|
    @limits << value
  end
end

describe "ordered_flag_group" do
  it "delivers occurrences in command-line order across spellings" do
    inst = FilterCli.parse(["--include", "a", "--exclude", "b", "--include", "c"])
    inst.rules.should eq([{"include", "a"}, {"exclude", "b"}, {"include", "c"}])
  end

  it "strips the leading dashes from the key" do
    FilterCli.parse(["--exclude", "x"]).rules.should eq([{"exclude", "x"}])
  end

  it "accepts =-joined values and interleaves with ordinary flags" do
    inst = FilterCli.parse(["--include=a", "--verbose", "--exclude=b"])
    inst.rules.should eq([{"include", "a"}, {"exclude", "b"}])
    inst.verbose.should be_true
  end

  it "supports several independent groups" do
    inst = FilterCli.parse(["--max-size", "10M", "--include", "a"])
    inst.limits.should eq(["10M"])
    inst.rules.should eq([{"include", "a"}])
  end

  it "converts ArgumentError from the block into a ParseError with the spelling" do
    expect_raises(Shell::AutoComplete::ParseError, /--include: empty pattern/) do
      FilterCli.parse(["--include", ""])
    end
  end

  it "requires a value like any value flag" do
    expect_raises(Shell::AutoComplete::ParseError, /--include requires a value/) do
      FilterCli.parse(["--include"])
    end
  end

  it "logs occurrences in parsed_occurrences" do
    inst = FilterCli.parse(["--include", "a"])
    inst.parsed_occurrences.should eq([{"--include", "a"}])
  end

  it "lists members in help with their descriptions" do
    rendered = FilterCli.help
    rendered.should contain("--include")
    rendered.should contain("PATTERN: include matching files")
    rendered.should contain("--exclude")
  end

  it "offers members in completion" do
    candidates = FilterCli.completion_candidates(["filt", "--in"], 1, "--in", "filt")
    candidates.should contain("--include")
  end
end

describe "ordered_flag_group compile guards" do
  it "participates in duplicate-name detection" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command DupGroup, name: "x", description: "x" do
        flag include_all : Bool = false, "--include", "Include everything"
        ordered_flag_group "Rules", {"--include" => "PATTERN"} do |key, value|
          @rules = {key, value}
        end
        property rules : {String, String}?
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --include")
  end

  it "rejects short-option members" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command ShortGroup, name: "x", description: "x" do
        ordered_flag_group "Rules", {"-i" => "PATTERN"} do |key, value|
        end
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("must be long options")
  end

  it "rejects a block with the wrong arity" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command ArityGroup, name: "x", description: "x" do
        ordered_flag_group "Rules", {"--include" => "PATTERN"} do |key|
        end
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("exactly two arguments")
  end
end
