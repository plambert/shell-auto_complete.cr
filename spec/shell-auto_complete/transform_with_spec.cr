require "../spec_helper"

Shell::AutoComplete.command CustomCli, name: "c", description: "x" do
  flag count : Int32?, "--count", "c", transform_with: :ten_times

  def self.ten_times(value : String) : Int32
    value.to_i * 10
  end
end

Shell::AutoComplete.command DefaultIntCli, name: "d", description: "x" do
  flag count : Int32?, "--count", "c"
end

describe "transform_with:" do
  it "uses the named class method instead of the type's __arg_transform" do
    CustomCli.parse(["--count", "3"]).count.should eq(30)
  end

  it "still falls back to the type transformer when transform_with is absent" do
    DefaultIntCli.parse(["--count", "3"]).count.should eq(3)
  end
end
