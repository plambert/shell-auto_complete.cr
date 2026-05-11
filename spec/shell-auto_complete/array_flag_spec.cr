require "../spec_helper"

Shell::AutoComplete.command ArrCli, name: "a", description: "x" do
  flag tags : Array(String) = [] of String, "--tag", "t"
end

Shell::AutoComplete.command ArrSemCli, name: "as", description: "x" do
  flag tags : Array(String) = [] of String, "--tag", "t", delimiter: ";"
end

Shell::AutoComplete.command ArrNoSplitCli, name: "ans", description: "x" do
  flag tags : Array(String) = [] of String, "--tag", "t", delimiter: nil
end

describe "Array(T) flag" do
  it "starts empty when flag absent" do
    ArrCli.parse([] of String).tags.should eq([] of String)
  end

  it "accumulates across multiple occurrences" do
    ArrCli.parse(["--tag", "a", "--tag", "b"]).tags.should eq(["a", "b"])
  end

  it "splits a single occurrence on default delimiter ','" do
    ArrCli.parse(["--tag", "a,b,c"]).tags.should eq(["a", "b", "c"])
  end

  it "respects custom delimiter" do
    ArrSemCli.parse(["--tag", "a;b"]).tags.should eq(["a", "b"])
  end

  it "treats nil delimiter as no splitting" do
    ArrNoSplitCli.parse(["--tag", "a,b"]).tags.should eq(["a,b"])
  end

  it "combines accumulation and splitting" do
    ArrCli.parse(["--tag", "a,b", "--tag", "c"]).tags.should eq(["a", "b", "c"])
  end
end
