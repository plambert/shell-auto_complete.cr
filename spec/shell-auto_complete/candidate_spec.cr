require "../spec_helper"

describe Shell::AutoComplete::Candidate do
  it "stores a value and optional description" do
    c = Shell::AutoComplete::Candidate.new(value: "foo", description: "the foo")
    c.value.should eq("foo")
    c.description.should eq("the foo")
  end

  it "allows nil description" do
    c = Shell::AutoComplete::Candidate.new(value: "bar")
    c.description.should be_nil
  end
end
