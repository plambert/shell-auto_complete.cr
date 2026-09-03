require "../spec_helper"

# Named flag catalog: common_flag defines reusable flags once; import_flags
# pulls selected subsets into commands, where they behave as if declared
# directly (parse, help, completion, duplicate detection, override).

private def compile_fragment(body : String) : {Process::Status, String}
  src = <<-CR
    require "../src/shell-auto_complete"
    #{body}
    CR
  tmp = File.tempfile("sac-catalog", ".cr", dir: spec_tmp_dir)
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

# A catalog of listing flags, modeled on a container tool's `ls`-style
# subcommands drawing overlapping-but-distinct subsets.
enum CatalogFormat
  Table
  Json
  Yaml
end

Shell::AutoComplete.common_flag :format,
  format : CatalogFormat = CatalogFormat::Table, "--format", "Output format"
Shell::AutoComplete.common_flag :filter,
  filter : Array(String) = [] of String, "--filter", "-f", "Filter (key=value)", delimiter: nil
Shell::AutoComplete.common_flag :quiet,
  quiet : Bool = false, "--quiet", "-q", "Only display IDs"
Shell::AutoComplete.common_flag :all,
  all : Bool = false, "--all", "-a", "Include stopped"
Shell::AutoComplete.common_flag :digests,
  digests : Bool = false, "--digests", "Show content digests"

Shell::AutoComplete.command CatalogPs, name: "ps", description: "List containers" do
  import_flags :format, :filter, :quiet, :all

  def run
  end
end

Shell::AutoComplete.command CatalogImages, name: "images", description: "List images" do
  import_flags :format, :filter, :quiet, :digests

  def run
  end
end

describe "common_flag / import_flags" do
  it "parses an imported value flag" do
    CatalogPs.parse(["--format", "json"]).format.should eq(CatalogFormat::Json)
  end

  it "parses an imported flag's alias/short and options (delimiter)" do
    inst = CatalogPs.parse(["-f", "a=1", "--filter", "b=2"])
    inst.filter.should eq(["a=1", "b=2"])
  end

  it "lets different commands import different subsets" do
    CatalogPs.parse(["--all"]).all.should be_true
    CatalogImages.parse(["--digests"]).digests.should be_true
  end

  it "rejects a flag the command did not import" do
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --digests/) do
      CatalogPs.parse(["--digests"])
    end
    expect_raises(Shell::AutoComplete::ParseError, /unknown flag: --all/) do
      CatalogImages.parse(["--all"])
    end
  end

  it "renders imported flags in help with their catalogued descriptions and placeholders" do
    rendered = CatalogPs.help
    rendered.should contain("--format")
    rendered.should contain("Output format")
    rendered.should contain("table|json|yaml")
    rendered.should contain("Only display IDs")
    rendered.should_not contain("Show content digests")
  end

  it "offers imported flags in completion" do
    CatalogPs.completion_candidates(["ps", "--fi"], 1, "--fi", "ps").should contain("--filter")
  end

  it "supports flag_given? on imported flags" do
    CatalogPs.parse(["--quiet"]).flag_given?(:quiet).should be_true
    CatalogPs.parse([] of String).flag_given?(:quiet).should be_false
  end
end

describe "import_flags compile-time behavior" do
  it "participates in duplicate detection against a directly declared flag" do
    status, err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.common_flag :format, format : String?, "--format", "Catalog format"
      Shell::AutoComplete.command DupImport, name: "x", description: "x" do
        flag format : String?, "--format", "Own format"
        import_flags :format
      end
      FRAGMENT
    status.success?.should be_false
    err.should contain("duplicate flag name --format")
    err.should contain("override: true")
  end

  it "rejects an unknown catalog name" do
    status, _err = compile_fragment <<-FRAGMENT
      Shell::AutoComplete.command BadImport, name: "x", description: "x" do
        import_flags :nonexistent
      end
      FRAGMENT
    status.success?.should be_false
  end
end
