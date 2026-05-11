require "../spec_helper"

describe Shell::AutoComplete::CompletionContext do
  it "exposes current_word, prior_words, and cword index" do
    ctx = Shell::AutoComplete::CompletionContext.new(
      words: ["mycli", "build", "--flag", "value"],
      cword: 3,
    )
    ctx.current_word.should eq("value")
    ctx.prior_words.should eq(["mycli", "build", "--flag"])
  end

  it "treats cword past the end as empty current_word" do
    ctx = Shell::AutoComplete::CompletionContext.new(
      words: ["mycli", "build"],
      cword: 2,
    )
    ctx.current_word.should eq("")
  end
end
