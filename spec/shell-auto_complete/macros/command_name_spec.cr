require "../../spec_helper"

Shell::AutoComplete.command TopLevel, description: "top-level"
Shell::AutoComplete.command NamedCmd, name: "explicit", description: "x"

describe "command_name" do
  it "defaults to File.basename(PROGRAM_NAME) when name: is omitted" do
    TopLevel.command_name.should eq(File.basename(PROGRAM_NAME))
  end

  it "returns the explicit name when name: is given" do
    NamedCmd.command_name.should eq("explicit")
  end
end
