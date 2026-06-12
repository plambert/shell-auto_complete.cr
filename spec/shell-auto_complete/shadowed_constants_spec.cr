require "../spec_helper"
require "log"

# Issue #9: generated code must emit fully qualified type paths. A command
# defined inside a namespace with its own `Log` (the standard
# `Log = ::Log.for ...` pattern) or `Path` constant must still compile when
# its flags/positionals use the top-level stdlib types.
module ShadowedConstants
  Log  = ::Log.for("shadowed")
  Path = "not the stdlib Path"

  Shell::AutoComplete.command ShadowCli, name: "shadow", description: "lives in a shadowing namespace" do
    flag level : ::Log::Severity?, "--level", "Log level"
    flag levels : Array(::Log::Severity) = [] of ::Log::Severity, "--levels", "Several log levels", delimiter: ","
    flag tags : Set(::Log::Severity) = Set(::Log::Severity).new, "--tags", "Severity set", delimiter: ","
    flag overrides : Hash(String, ::Log::Severity) = {} of String => ::Log::Severity, "--override", "Per-source severity"
    # File's __arg_transform returns Path, so the property is storage-remapped
    # to the (shadowed) Path type.
    flag input : ::File?, "--input", "Input file"
    positional source : ::Path?, "Source path"
  end
end

describe "commands inside namespaces that shadow stdlib constants" do
  it "parses a scalar flag of a shadowed type" do
    ShadowedConstants::ShadowCli.parse(["--level", "warn"]).level.should eq(::Log::Severity::Warn)
  end

  it "parses an Array flag of a shadowed element type" do
    inst = ShadowedConstants::ShadowCli.parse(["--levels", "warn,error"])
    inst.levels.should eq([::Log::Severity::Warn, ::Log::Severity::Error])
  end

  it "parses a Set flag of a shadowed element type" do
    inst = ShadowedConstants::ShadowCli.parse(["--tags", "info"])
    inst.tags.should eq(Set{::Log::Severity::Info})
  end

  it "parses a Hash flag of a shadowed value type" do
    inst = ShadowedConstants::ShadowCli.parse(["--override", "db=debug"])
    inst.overrides.should eq({"db" => ::Log::Severity::Debug})
  end

  it "parses a storage-remapped flag whose storage type is shadowed" do
    inst = ShadowedConstants::ShadowCli.parse(["--input", __FILE__])
    inst.input.should eq(::Path.new(__FILE__))
  end

  it "parses a positional of a shadowed type" do
    inst = ShadowedConstants::ShadowCli.parse(["some/path"])
    inst.source.should eq(::Path.new("some/path"))
  end
end
