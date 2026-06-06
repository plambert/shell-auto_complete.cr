module Shell::AutoComplete::Completion
  # Maps a completion cursor onto a positional-argument slot.
  module Positional
    # Returns the 0-based positional slot the cursor sits on, accounting for
    # flags and the values they consume, or `nil` when the cursor is *not* on a
    # positional (it's a flag name, or the value of a value-taking flag).
    #
    # `value_flag_names` is the set of flag tokens (canonical, aliases, short
    # forms) for flags that take a value; bool flags are excluded because they
    # consume no following token. Mirrors the parser's argument consumption:
    # `--flag=value` is a single token, a `--` terminator forces everything
    # after it to be positional.
    def self.index_at(words : Array(String), cword : Int32, value_flag_names : Set(String)) : Int32?
      current = cword < words.size ? words[cword] : ""

      after_terminator = false
      pos = 0
      i = 1
      while i < cword
        tok = words[i]
        if after_terminator
          pos += 1
          i += 1
          next
        end
        if tok == "--"
          after_terminator = true
          i += 1
          next
        end
        if flag_token?(tok)
          # `--flag=value` is self-contained; a bare value flag eats the next token.
          if !tok.includes?('=') && value_flag_names.includes?(tok)
            i += 2
          else
            i += 1
          end
          next
        end
        pos += 1
        i += 1
      end

      unless after_terminator
        # Cursor on a flag name → not a positional.
        return if flag_token?(current)
        # Cursor on a value-taking flag's value → not a positional.
        prev = cword > 0 ? words[cword - 1] : ""
        return if !prev.includes?('=') && value_flag_names.includes?(prev)
      end

      pos
    end

    # A token that looks like a flag: starts with `-` but isn't a bare `-`.
    def self.flag_token?(tok : String) : Bool
      tok.size > 1 && tok.starts_with?('-')
    end
  end
end
