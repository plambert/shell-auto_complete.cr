module Shell::AutoComplete::Completion
  module Dispatcher
    # Returns true if argv[0] == "__complete" — handler consumed.
    def self.handle(klass : ::Shell::AutoComplete::Command.class, argv : Array(String), stdout : IO) : Bool
      return false unless argv.first? == "__complete"
      cword = argv[1]?.try(&.to_i) || 0
      words = argv[2..]

      # If no words (yet), nothing to complete.
      return true if words.empty?

      # Descend into subcommands: scan the words before the cursor; a token
      # naming a subcommand of the current target descends (the token is
      # removed and cword decremented), anything else — a flag of the
      # routing command or a value it consumed — is skipped, so shared flags
      # before the subcommand word don't block descent.
      target = klass
      scan_index = 1
      words = words.dup
      while scan_index < cword && scan_index < words.size
        token = words[scan_index]
        break if token == "--"
        if subcommand = target.subcommand_named(token)
          target = subcommand
          words.delete_at(scan_index)
          cword -= 1
        else
          scan_index += 1
        end
      end

      current = cword < words.size ? words[cword] : ""
      prev = cword > 0 ? words[cword - 1] : ""

      candidates = target.completion_candidates(words, cword, current, prev)
      candidates.each { |candidate| stdout.puts candidate }
      true
    end
  end
end
