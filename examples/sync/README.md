# Example: sync clone

An rsync-style file sync CLI built with [shell-auto_complete](../../), showcasing command-line ordering and value validation.

## Build

```sh
crystal build examples/sync/sync.cr -o sync
```

## Try it

```sh
# Filter rules apply in the order you type them — first match wins.
./sync --include '*.rb' --exclude 'test/*' --include 'lib/*' src dst

# Repeatable SRC:DST path mappings, each parsed by a per-element transform.
./sync --map src/a:dst/a --map src/b:dst/b src dst

# Set arithmetic: add and remove features in one --with list, plus another.
./sync --with +delete,-perms --with backup src dst

# Validated values: a choice, a regex-checked rename, a bounded bandwidth cap.
./sync --checksum sha256 --rename 's/foo/bar/' --bwlimit 500000 src dst

# Print the filter syntax and exit before any other validation runs.
./sync --list-filters

# These are rejected with a non-zero exit and a message naming the flag:
./sync --map bad src dst              # malformed mapping (needs SRC:DST)
./sync --bwlimit 999999999 src dst    # outside the 0..1000000 range
./sync --checksum crc32 src dst       # not one of none|md5|sha256
./sync --rename 'nope' src dst        # does not match the rename regex
```

Every run prints the parsed configuration, the filter rules in command-line
order, the path mappings, and a **re-emit** line that reconstructs an
equivalent invocation from `parsed_occurrences` — recovering the exact order
the flags were typed.

## Shell completion

```sh
./sync --shell-completion bash > /etc/bash_completion.d/sync
./sync --shell-completion zsh  > ~/.zsh/completions/_sync
./sync --shell-completion fish > ~/.config/fish/completions/sync.fish
```

## Demonstrates

- `ordered_flag_group` for `--include` / `--exclude` rules where the order
  between spellings is the semantics; the block records each into a property in
  argv order, and `run` applies them in that order
- `parsed_occurrences` re-emit: reconstruct an equivalent command line from the
  recorded flag occurrences
- `choices:` on `--checksum` (`none|md5|sha256`)
- `range:` on `--bwlimit` (`0..1000000`) and `matches:` on `--rename` (regex)
- `set_operations: true` on a `Set(String)` flag (`--with +feature -feature`)
- `immediate:` on a `Bool` flag (`--list-filters`) that prints and exits before
  full validation, via `immediate: :print_filters`
- Per-element `transform_with:` on a collection flag (`--map SRC:DST`) with
  `delimiter: nil`, raising `ArgumentError` on malformed input
- Value placeholders: embedded (`"--max-size SIZE"`) and explicit
  (`placeholder: "TAG"`)
- A variadic `positionals paths : Array(Path)` with `min: 2` (`SRC... DEST`)
- `--help` and `--shell-completion` built-in flags provided by the shard
