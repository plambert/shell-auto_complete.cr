require "../spec_helper"

Shell::AutoComplete.command PortCli, name: "p", description: "x" do
  flag port : Int32?, "--port", "p", range: 1..65535
end

Shell::AutoComplete.command FloatRangeCli, name: "fr", description: "x" do
  flag ratio : Float64?, "--ratio", "r", range: 0.0..1.0
end

Shell::AutoComplete.command UnboundedCli, name: "u", description: "x" do
  flag n : Int32?, "--n", "n"
end

describe "range: validator" do
  it "accepts an in-range Int32" do
    PortCli.parse(["--port", "8080"]).port.should eq(8080)
  end

  it "rejects an out-of-range Int32" do
    expect_raises(Shell::AutoComplete::ParseError, /out of range/) do
      PortCli.parse(["--port", "70000"])
    end
  end

  it "accepts the lower bound" do
    PortCli.parse(["--port", "1"]).port.should eq(1)
  end

  it "accepts the upper bound" do
    PortCli.parse(["--port", "65535"]).port.should eq(65535)
  end

  it "validates Float64 ranges too" do
    FloatRangeCli.parse(["--ratio", "0.5"]).ratio.should eq(0.5)
    expect_raises(Shell::AutoComplete::ParseError) do
      FloatRangeCli.parse(["--ratio", "1.5"])
    end
  end

  it "allows numeric flags without range:" do
    UnboundedCli.parse(["--n", "999999"]).n.should eq(999999)
  end
end
