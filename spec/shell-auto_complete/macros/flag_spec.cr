require "../../spec_helper"

Shell::AutoComplete.command Cli1, name: "cli1", description: "test" do
  flag message : String?, "--message", "the message"
end

Shell::AutoComplete.command Cli2, name: "cli2", description: "test" do
  flag tag : String?, %w[--tag --label -t], "a tag"
end

describe "flag macro (basic)" do
  it "generates a property with the declared type" do
    inst = Cli1.new
    inst.message.should be_nil
    inst.message = "hello"
    inst.message.should eq("hello")
  end

  it "records the canonical long flag" do
    Cli1.flag_info("message").canonical.should eq("--message")
  end

  it "records the description" do
    Cli1.flag_info("message").description.should eq("the message")
  end

  it "records aliases when given as an array" do
    Cli2.flag_info("tag").aliases.should eq(["--label"])
  end

  it "records the short flag when given" do
    Cli2.flag_info("tag").short.should eq("-t")
  end

  it "leaves short nil when not given" do
    Cli1.flag_info("message").short.should be_nil
  end
end
