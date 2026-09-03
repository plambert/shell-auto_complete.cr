require "../spec_helper"

# An enum flag given a name that matches no member names the allowed values in
# the same "X is not one of a, b, c" wording a `choices:` flag uses, rather
# than the enum's Crystal type — the scalar path prefixes the flag on top.

enum EnumMsgProfile
  Obligation
  Acquisition
end

@[Flags]
enum EnumMsgPerm
  Read
  Write
end

Shell::AutoComplete.command EnumMsgCli, name: "enummsg", description: "x" do
  flag profile : EnumMsgProfile?, "--profile", "p"
  flag perm : EnumMsgPerm = EnumMsgPerm::None, "--perm", "q"
end

describe "enum flag rejection message" do
  it "names the allowed members, kebab-cased, instead of the Crystal type" do
    error = expect_raises(Shell::AutoComplete::ParseError) do
      EnumMsgCli.parse(["--profile", "wat"])
    end
    error.message.should eq("--profile: wat is not one of obligation, acquisition")
  end

  it "still accepts any case and -/_ spelling" do
    EnumMsgCli.parse(["--profile", "Acquisition"]).profile.should eq(EnumMsgProfile::Acquisition)
    EnumMsgCli.parse(["--profile", "ACQUISITION"]).profile.should eq(EnumMsgProfile::Acquisition)
  end

  it "reports the bad part of a comma-separated @[Flags] value" do
    error = expect_raises(Shell::AutoComplete::ParseError) do
      EnumMsgCli.parse(["--perm", "read,execute"])
    end
    error.message.should match(/\A--perm: execute is not one of .*\bread\b.*\bwrite\b/)
  end
end
