module Shell::AutoComplete::Completion
  module Dispatcher
    # Returns true if argv[0] == "__complete" — handler consumed.
    def self.handle(klass : ::Shell::AutoComplete::Command.class, argv : Array(String), stdout : IO) : Bool
      return false unless argv.first? == "__complete"
      cword = argv[1]?.try(&.to_i) || 0
      words = argv[2..]

      # If no words (yet), nothing to complete.
      return true if words.empty?

      # Descend into subcommands: while the cursor is past the first argument and
      # words[1] names a subcommand of the current target, shift that token off
      # (so it becomes the new index-0 "program name" slot) and decrement cword,
      # recursing into the subcommand class.
      target = klass
      while cword >= 2 && words.size >= 2
        subcommand = target.subcommand_named(words[1])
        break unless subcommand
        target = subcommand
        words = words[1..]
        cword -= 1
      end

      current = cword < words.size ? words[cword] : ""
      prev = cword > 0 ? words[cword - 1] : ""

      candidates = target.completion_candidates(words, cword, current, prev)
      candidates.each { |candidate| stdout.puts candidate }
      true
    end
  end
end
