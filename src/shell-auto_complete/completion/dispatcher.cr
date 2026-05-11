module Shell::AutoComplete::Completion
  module Dispatcher
    # Returns true if argv[0] == "__complete" — handler consumed.
    def self.handle(klass : ::Shell::AutoComplete::Command.class, argv : Array(String), stdout : IO) : Bool
      return false unless argv.first? == "__complete"
      cword = argv[1]?.try(&.to_i) || 0
      words = argv[2..]

      # If no words (yet), nothing to complete.
      return true if words.empty?

      current = cword < words.size ? words[cword] : ""
      prev = cword > 0 ? words[cword - 1] : ""

      candidates = klass.completion_candidates(words, cword, current, prev)
      candidates.each { |candidate| stdout.puts candidate }
      true
    end
  end
end
