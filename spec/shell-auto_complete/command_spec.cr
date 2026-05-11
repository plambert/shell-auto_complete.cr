require "../spec_helper"

class EmptyCommand < Shell::AutoComplete::Command
end

describe Shell::AutoComplete::Command do
  it "is subclassable" do
    EmptyCommand.new.should be_a(Shell::AutoComplete::Command)
  end

  it "raises a NotRunnable when #run is called without override" do
    expect_raises(Shell::AutoComplete::NotRunnable) do
      EmptyCommand.new.run
    end
  end
end
