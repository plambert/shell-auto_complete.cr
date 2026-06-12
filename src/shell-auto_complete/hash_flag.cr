module Shell::AutoComplete
  # Shared key grammar for `Hash(String, T)` flags. The delete pattern is
  # DERIVED from the key pattern so the two cannot drift: widening the key
  # charset automatically widens what `-key` can delete.
  module HashFlag
    # A key starts with a word character and may continue with word
    # characters, dots, colons, and dashes — dots/colons admit namespaced
    # keys (`a.b=1`, `log:level=debug`). Keys can never start with `-`,
    # which is what keeps the bare `-key` delete form unambiguous.
    KEY_SOURCE = "[A-Za-z0-9_][A-Za-z0-9_.:\\-]*"

    KEY_VALUE_RE = /\A(#{KEY_SOURCE})=(.*)\z/m
    DELETE_RE    = /\A-(#{KEY_SOURCE})\z/
    # `-key=value` is always a mistake — assignment never takes a dash,
    # deletion never takes a value. Matched to give a targeted error.
    DELETE_ASSIGN_RE = /\A-(#{KEY_SOURCE})=/m
  end
end
