require "../spec_helper"

Shell::AutoComplete.command IntCli, name: "int", description: "x" do
  flag count : Int32?, "--count", "c"
end

Shell::AutoComplete.command FloatCli, name: "float", description: "x" do
  flag ratio : Float64?, "--ratio", "r"
end

Shell::AutoComplete.command IntDefaultCli, name: "intd", description: "x" do
  flag count : Int32 = 5, "--count", "c"
end

describe "numeric transformers" do
  it "parses Int32 via --count" do
    IntCli.parse(["--count", "42"]).count.should eq(42)
  end

  it "parses Float64 via --ratio" do
    FloatCli.parse(["--ratio", "3.14"]).ratio.should eq(3.14)
  end

  it "defaults a non-nullable Int32 to its declared value when flag is absent" do
    IntDefaultCli.parse([] of String).count.should eq(5)
  end

  it "raises on non-numeric values for Int32, naming the flag" do
    expect_raises(Shell::AutoComplete::ParseError, /--count: /) do
      IntCli.parse(["--count", "abc"])
    end
  end
end

Shell::AutoComplete.command StrCli, name: "str", description: "x" do
  flag message : String?, "--message", "m"
end

describe "String transformer (no-op)" do
  it "passes strings through unchanged" do
    StrCli.parse(["--message", "hello"]).message.should eq("hello")
  end
end
