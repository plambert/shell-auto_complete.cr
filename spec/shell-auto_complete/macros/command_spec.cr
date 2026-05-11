require "../../spec_helper"

Shell::AutoComplete.command Foo, name: "foo", description: "the foo command"

describe "command macro" do
  it "creates a Command subclass" do
    Foo.new.should be_a(Shell::AutoComplete::Command)
  end

  it "the class can be instantiated" do
    Foo.new.should be_a(Foo)
  end
end
