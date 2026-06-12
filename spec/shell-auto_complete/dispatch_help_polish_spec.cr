require "../spec_helper"

# Issue #21: help layout hooks, -- respected by the --help intercept, and
# immediate flags.

Shell::AutoComplete.command LayoutLeaf, name: "lleaf", description: "Leaf for layout" do
  def run
  end
end

Shell::AutoComplete.command LayoutCli, name: "layout", description: "The description prose",
  help_sections: [:subcommands, :options, :description] do
  subcommand LayoutLeaf
  flag verbose : Bool = false, "--verbose", "Verbose output"
end

Shell::AutoComplete.command GroupedCli, name: "grouped", description: "x" do
  flag verbose : Bool = false, "--verbose", "Verbose output"
  flag host : String?, "--host", "Server host", group: "Connection options"
  flag port : Int32?, "--port", "Server port", group: "Connection options"
  flag retries : Int32?, "--retries", "Retry count", group: "Robustness"
end

Shell::AutoComplete.command DashDashCli, name: "dd", description: "x" do
  class_property ran_with : Array(String) = [] of String
  positionals words : Array(String), "Words"

  def run
    self.class.ran_with = words
  end
end

Shell::AutoComplete.command ImmediateCli, name: "imm", description: "x" do
  class_property printed : Array(String) = [] of String

  flag list_formats : Bool = false, "--list-formats", "List formats", immediate: :print_formats
  flag version_info : Bool = false, "--version-info", "Version info", immediate: true
  flag level : Int32?, "--level", "Level"

  def print_formats
    self.class.printed << "formats"
  end

  def immediate_version_info
    self.class.printed << "version"
  end

  def run
    self.class.printed << "ran"
  end
end

describe "help section order" do
  it "renders sections in the declared order" do
    rendered = LayoutCli.help
    subcommands_at = rendered.index("Subcommands:").not_nil!
    options_at = rendered.index("Options:").not_nil!
    description_at = rendered.index("The description prose").not_nil!
    (subcommands_at < options_at).should be_true
    (options_at < description_at).should be_true
  end

  it "keeps the default order without help_sections:" do
    rendered = GroupedCli.help
    rendered.index("x").not_nil!.should be < rendered.index("Options:").not_nil!
  end
end

describe "option grouping" do
  it "renders grouped flags under their own heading, after ungrouped options" do
    rendered = GroupedCli.help
    rendered.should contain("Connection options:")
    rendered.should contain("Robustness:")
    options_at = rendered.index("Options:").not_nil!
    connection_at = rendered.index("Connection options:").not_nil!
    (options_at < connection_at).should be_true
    host_at = rendered.index("--host").not_nil!
    (connection_at < host_at).should be_true
  end
end

describe "-- respected by help intercepts" do
  it "treats --help after -- as a positional" do
    output = IO::Memory.new
    DashDashCli.ran_with = [] of String
    DashDashCli.dispatch(["--", "--help"], stdout: output, rescue_errors: false)
    output.to_s.should_not contain("Usage:")
    DashDashCli.ran_with.should eq(["--help"])
  end

  it "still intercepts --help before --" do
    output = IO::Memory.new
    DashDashCli.dispatch(["--help", "--", "x"], stdout: output, rescue_errors: false)
    output.to_s.should contain("Usage:")
  end
end

describe "immediate flags" do
  it "fires the designated handler even when the rest of the line is invalid" do
    ImmediateCli.printed = [] of String
    inst = ImmediateCli.dispatch(["--bogus-flag", "--list-formats"], rescue_errors: false)
    ImmediateCli.printed.should eq(["formats"])
    inst.as(ImmediateCli).list_formats.should be_true
  end

  it "uses the immediate_<name> convention for immediate: true" do
    ImmediateCli.printed = [] of String
    ImmediateCli.dispatch(["--version-info"], rescue_errors: false)
    ImmediateCli.printed.should eq(["version"])
  end

  it "does not fire after --" do
    ImmediateCli.printed = [] of String
    expect_raises(Shell::AutoComplete::ParseError, /too many positional/) do
      ImmediateCli.dispatch(["--", "--list-formats"], rescue_errors: false)
    end
    ImmediateCli.printed.should be_empty
  end

  it "does not interfere with normal parsing when absent" do
    ImmediateCli.printed = [] of String
    ImmediateCli.dispatch(["--level", "3"], rescue_errors: false)
    ImmediateCli.printed.should eq(["ran"])
  end
end
