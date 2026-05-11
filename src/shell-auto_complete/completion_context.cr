module Shell::AutoComplete
  struct CompletionContext
    getter words : Array(String)
    getter cword : Int32

    def initialize(@words : Array(String), @cword : Int32)
    end

    def current_word : String
      cword < words.size ? words[cword] : ""
    end

    def prior_words : Array(String)
      words[0, cword]
    end
  end
end
