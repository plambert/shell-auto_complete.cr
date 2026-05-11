require "../spec_helper"

@[Flags]
enum Perm
  Read
  Write
  Execute
end

Shell::AutoComplete.command FlagsCli, name: "f", description: "x" do
  flag perms : Perm = Perm::None, "--perms", "p"
end

describe "@[Flags] enum" do
  it "parses single value" do
    inst = FlagsCli.parse(["--perms", "read"])
    inst.perms.read?.should be_true
    inst.perms.write?.should be_false
  end

  it "parses comma-separated list" do
    inst = FlagsCli.parse(["--perms", "read,write"])
    inst.perms.read?.should be_true
    inst.perms.write?.should be_true
    inst.perms.execute?.should be_false
  end

  it "parses all three" do
    inst = FlagsCli.parse(["--perms", "read,write,execute"])
    inst.perms.includes?(Perm::Read).should be_true
    inst.perms.includes?(Perm::Write).should be_true
    inst.perms.includes?(Perm::Execute).should be_true
  end
end
