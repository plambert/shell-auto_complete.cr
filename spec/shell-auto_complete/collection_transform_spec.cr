require "../spec_helper"

# Issue #16: transform_with:/validate_with: and the per-flag method
# conventions are honored per element on Array/Set/Hash flags.

Shell::AutoComplete.command CollTransformCli, name: "ct", description: "x" do
  flag map : Array(Tuple(String, String)) = [] of Tuple(String, String),
    "--map", "Rewrite path prefix SRC to DST", delimiter: nil,
    transform_with: :parse_mapping

  flag ports : Array(Int32) = [] of Int32, "--ports", "Ports",
    validate_with: :check_port

  flag tags : Set(String) = Set(String).new, "--tags", "Tags",
    set_operations: true, transform_with: :normalize_tag

  flag weights : Hash(String, Int32) = {} of String => Int32, "--weight", "Weights",
    validate_with: :check_weight

  flag codes : Array(String) = [] of String, "--codes", "Codes"

  def self.parse_mapping(value : String) : Tuple(String, String)
    src, sep, dst = value.partition(':')
    raise ArgumentError.new("expected SRC:DST, got #{value.inspect}") if sep.empty? || src.empty? || dst.empty?
    {src, dst}
  end

  def self.check_port(value : Int32) : Bool | String
    return "port out of range: #{value}" unless 1 <= value <= 65535
    true
  end

  def self.normalize_tag(value : String) : String
    value.downcase
  end

  def self.check_weight(value : Int32) : Bool
    value >= 0
  end

  # Per-flag method convention: overrides the stock String transform for
  # every element of --codes.
  def self.__arg_transform_codes(value : String) : String
    value.upcase
  end
end

describe "collection transform_with:" do
  it "applies the custom transform per element" do
    inst = CollTransformCli.parse(["--map", "a:b", "--map", "c:d"])
    inst.map.should eq([{"a", "b"}, {"c", "d"}])
  end

  it "rejects a malformed element at parse time with the flag's name" do
    expect_raises(Shell::AutoComplete::ParseError, /--map: expected SRC:DST, got "nope"/) do
      CollTransformCli.parse(["--map", "nope"])
    end
  end

  it "applies the transform to every delimiter-split part" do
    inst = CollTransformCli.parse(["--tags", "Alpha,BETA"])
    inst.tags.should eq(Set{"alpha", "beta"})
  end

  it "transforms set-operation payloads after stripping the +/- prefix" do
    inst = CollTransformCli.parse(["--tags", "Alpha,Beta", "--tags", "-ALPHA"])
    inst.tags.should eq(Set{"beta"})
  end
end

describe "collection validate_with:" do
  it "accepts valid elements" do
    CollTransformCli.parse(["--ports", "80,443"]).ports.should eq([80, 443])
  end

  it "rejects an invalid element with the validator's message and the flag's name" do
    expect_raises(Shell::AutoComplete::ParseError, /--ports: port out of range: 99999/) do
      CollTransformCli.parse(["--ports", "80,99999"])
    end
  end

  it "validates hash values" do
    CollTransformCli.parse(["--weight", "a=3"]).weights.should eq({"a" => 3})
    expect_raises(Shell::AutoComplete::ParseError, /--weight: not a valid weights/) do
      CollTransformCli.parse(["--weight", "a=-1"])
    end
  end
end

describe "collection per-flag method conventions" do
  it "uses __arg_transform_<name> for every element" do
    CollTransformCli.parse(["--codes", "ab,cd"]).codes.should eq(["AB", "CD"])
  end
end
