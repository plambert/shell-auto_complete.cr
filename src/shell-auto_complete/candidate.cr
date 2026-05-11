module Shell::AutoComplete
  struct Candidate
    getter value : String
    getter description : String?

    def initialize(@value : String, @description : String? = nil)
    end
  end
end
