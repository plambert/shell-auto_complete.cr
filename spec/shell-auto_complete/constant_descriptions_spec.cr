require "../spec_helper"

# Issue #18: descriptions, headers, and footers may be constant references
# (resolved at macro-expansion time when possible) or method references
# (resolved at help-render time), so help text can mirror the runtime
# constants that drive validation.

PRESETS         = %w[fast small balanced]
PRESET_HELP     = "Encoder preset (one of: #{PRESETS.join(", ")})"
CONST_DESC_HDR  = "Tool for preset-driven encoding"
PLAIN_CONST     = "A plain literal constant description"
POSITIONAL_DESC = "Output file path"

Shell::AutoComplete.command ConstDescCli, name: "cdesc", description: "x",
  header: CONST_DESC_HDR, footer: footer_text do
  flag preset : String?, "--preset", PRESET_HELP, choices: PRESETS
  flag mode : String?, "--mode", PLAIN_CONST
  flag rate : Int32?, "--rate", rate_description
  positional output : String?, description: POSITIONAL_DESC

  def self.footer_text : String
    "Presets available: #{PRESETS.join(" | ")}"
  end

  def self.rate_description : String
    "Sample rate in Hz"
  end
end

describe "constant and method references in help text" do
  it "renders a computed-constant flag description" do
    ConstDescCli.help.should contain("Encoder preset (one of: fast, small, balanced)")
  end

  it "renders a plain-literal constant flag description" do
    ConstDescCli.help.should contain("A plain literal constant description")
  end

  it "renders a method-reference flag description" do
    ConstDescCli.help.should contain("Sample rate in Hz")
  end

  it "renders a constant header and a method-reference footer" do
    rendered = ConstDescCli.help
    rendered.should contain("Tool for preset-driven encoding")
    rendered.should contain("Presets available: fast | small | balanced")
  end

  it "renders a constant positional description" do
    ConstDescCli.help.should contain("Output file path")
  end

  it "exposes the resolved text through flag_info" do
    ConstDescCli.flag_info("preset").description.should contain("one of: fast, small, balanced")
    ConstDescCli.flag_info("mode").description.should eq("A plain literal constant description")
  end

  it "keeps the constant-driven choices validating" do
    ConstDescCli.parse(["--preset", "fast"]).preset.should eq("fast")
    expect_raises(Shell::AutoComplete::ParseError) do
      ConstDescCli.parse(["--preset", "bogus"])
    end
  end
end
