# Changelog

All notable changes are documented here.

## [Unreleased]

### Added

- Compile-time duplicate flag-name detection. Every spelling a `flag` declaration produces — canonical, aliases, short form, the generated `--no-` negation, and enum `shortcut_flags:` switches — registers in a per-command registry, and a collision is now a compile error naming both flags instead of undefined behavior (previously the first declaration silently won at parse time while help showed both). (#10)
- `override: true` on `flag` for intentional redefinition (the mixin-override case). The overriding declaration replaces the prior flag wholesale: all of the replaced flag's spellings are freed, and parse, help, and completion follow the replacement. The overriding flag must bind a new property; the replaced property remains declared but is no longer set by parsing. (#10)

### Fixed

- Generated code now emits fully qualified type paths, so commands defined inside a namespace that shadows a top-level constant (the standard `Log = ::Log.for self` pattern, a local `Path` constant, etc.) compile and parse correctly. Resolved types spliced by the parse/help/completion generators get a `::` prefix; storage-remapped property types (e.g. `File`/`Dir` → `Path`, whose spelling comes from the transformer's own source file) are qualified the same way. User-written type spellings are still respliced verbatim, so relative paths that resolve in the user's namespace keep working. (#9)

## [1.2.0] - 2026-06-11

### Added

- `Shell::AutoComplete::Types::SetDelta` — a variadic positional type for set deltas. A positional typed `SetDelta` accepts `+name` (→ `true`), `-name` (→ `false`), and bare `name` (→ `true`) tokens and binds them into a `Hash(String, Bool)` (last write wins on a repeated key); `SetDelta.apply(set, delta)` applies the delta to a `Set(String)`. The parser gains a `dash_positionals` mode so a single-dash token that matches no flag spec (e.g. `-foo`) is treated as a positional instead of raising "unknown flag"; double-dash tokens and known flags are unaffected, so `--help`/`-v`/typo detection still work and known flags take precedence. `min:`/`max:` bound the number of distinct keys. Hash positionals are now rejected at compile time with a message pointing at `SetDelta` (the generic Hash positional path never worked).

## [1.1.1] - 2026-06-08

### Fixed

- Generated bash completion no longer tears filenames with spaces (or glob metacharacters) into multiple candidates. The wrapper built `COMPREPLY=( $(compgen -f -- "$cur") )`, whose unquoted command substitution word-splits each result on `$IFS` and then glob-expands it — so completing `my file.torrent` offered `my`, `file.torrent`. It now reads one candidate per line (`while IFS= read -r line; do COMPREPLY+=( "$line" ); done < <(compgen ...)`), preserving spaces and metacharacters verbatim. The plain `-W` candidate path is split on newlines only for the same reason. bash 3.2+ compatible. zsh (`_files`) and fish (`__fish_complete_path`) were already correct.

## [1.1.0] - 2026-06-06

### Added

- Positional arguments now get tab completion. `completion_candidates` resolves the cursor to a positional slot (walking past flags and the values they consume, honoring `--` and `--flag=value`) and dispatches to that positional's `complete_with:` method or its type's `__arg_complete`. Path-typed positionals (`Path`, `File`, `Dir`) complete against the filesystem: rather than enumerate entries in Crystal, `__complete` emits a directive sentinel (`__sac_complete_files__` / `__sac_complete_dirs__`) and the generated bash/zsh/fish wrappers turn it into the shell's own native completion (`compgen -f`/`-d` + `compopt -o filenames`, `_files`/`_files -/`, `__fish_complete_path`/`__fish_complete_directories`) — preserving `~` expansion, trailing slashes, and coloring. (#4)

### Fixed

- Scalar and variadic `File`/`Dir` positionals now compile. Their property was typed `File`/`Dir` while `__arg_transform` returns `Path`, so the generated parse code assigned a `Path` into a `File`/`Dir` slot. The `positional`/`positionals` macros now remap the property to the transformer's return type and record the declared type as `transformer_type:` in the annotation (mirroring the flag macro); parsing transforms through the declared type so the `File`/`Dir` existence checks still run, and completion resolves the directive from the declared type so a `Dir` positional emits the dirs directive rather than files. (#6)

## [1.0.3] - 2026-06-05

### Changed

- Internal: unified command-path construction. The `parent_prefix ? "#{parent_prefix} #{command_name}" : command_name` idiom — previously duplicated in `dispatch`, `help`, and `all_help` — is now a single `self.qualified_name(parent_prefix)` method. The error path (`ParseError#command_path`) no longer rebuilds the path bottom-up by prepending each level's bare name on unwind; instead the level that first raises seeds the already-fully-qualified `qualified_name` and outer levels leave it via `||=`. No observable behavior change; the help and error output are byte-identical.

## [1.0.2] - 2026-06-05

### Fixed

- Subcommand `--help` now renders a fully qualified `Usage:` line. Previously `mycli sub --help` showed `Usage: sub [options]` — the subcommand's bare name with no parent context. The qualified path is now threaded through `dispatch` → `help` → `Help.render` → `default_usage`: `dispatch` carries a `parent_prefix`, building the qualified name at each level and passing it to the matched child, so `mycli sub --help` shows `Usage: mycli sub [options]` and `mycli sub nested --help` shows `Usage: mycli sub nested [options]`. Explicit `usage:` overrides keep precedence. `all_help` now uses the same `parent_prefix` mechanism instead of a parallel `prefix` walk.

## [1.0.1] - 2026-06-05

### Fixed

- Shell completion now descends into subcommands. Previously `__complete` always ran against the root command, so `mycmd subcmd <TAB>` and `mycmd subcmd --<TAB>` produced no candidates. `Completion::Dispatcher.handle` now walks the words, shifting off each token that names a subcommand of the current target (decrementing `cword` as it goes) before computing candidates against the final target. Nested subcommand chains and flag-prefix filtering inside subcommands complete correctly. A new `self.subcommand_named` class method on every command performs the lookup.

## [1.0.0] - 2026-06-02

First stable release. The macro DSL, parser, help, and shell-completion APIs are now considered stable; no breaking changes from the 0.9.x line.

### Changed

- Minimum Crystal version lowered from `1.20.1` to `1.3.2`. The full spec suite (206 examples) passes on every Crystal release from 1.3.2 through 1.20.2; 1.2.2 and earlier fail to compile the macro DSL. A version-matrix harness (`spec/Dockerfile`, `spec/run-crystal-versions.sh`) sweeps Crystal releases newest-to-oldest to determine the floor.

### Fixed

- `Shell::AutoComplete::VERSION` now displays its resolved value (e.g. `"1.0.0"`) in the generated API docs instead of the raw `shards version` macro expression.
- Test suite no longer fails on Linux: a spec that compiled and executed a helper binary held the binary's file descriptor open across `exec`, which Linux rejects with `ETXTBSY` (macOS tolerates it).

## [0.9.2] - 2026-05-12

### Fixed

- Rescued errors now show the full command path. `multitool scan deep --bogus` now prints `multitool scan deep: unknown flag: --bogus` instead of just `multitool: ...`. Implemented via a `command_path` field on `ParseError` that each `dispatch` level prepends to before re-raising.

## [0.9.1] - 2026-05-12

### Fixed

- `--help` output now includes a `Positional arguments:` section listing each `positional` and `positionals` declaration with its name, description, and whether it is variadic. The default `Usage:` line also includes positional placeholders (e.g. `<name> <files...>`).
- Dispatching a subcommand parent with no arguments (empty `argv`) now prints help and returns `nil` instead of raising `NotRunnable`.
- `max:` option on `positionals` is now enforced at parse time; passing more values than the declared maximum raises `Shell::AutoComplete::ParseError`.
- Rescued parse errors in `dispatch` are now prefixed with the command name in conventional Unix format (`<cmd>: <message>`) instead of the bare `Error: ` prefix.

## [0.1.0] - 2026-05-10

Initial release.

### Fixed

- `<subcommand> --help` now prints the subcommand's help instead of the root command's. Sub-subcommands work the same way: `<parent> <child> --help` routes through to the leaf command's help text.

### Added

- `dispatch(argv, rescue_errors: true)` (default) catches `Shell::AutoComplete::ParseError` and `ArgumentError` raised during parsing/transforming/validating, prints a friendly `Error: …` message to STDERR, and exits 1. Pass `rescue_errors: false` to let exceptions propagate (useful for tests or programmatic embedding).
- `--all-help` flag (auto-generated on any command that declares `subcommand`s): prints the command's help plus the help of every descendant in the subcommand tree, separated by `==== <full path> ====` headers. Leaf commands (no subcommands declared) do NOT accept `--all-help` — it falls through as an unknown flag.
- **Macro DSL**: `command`, `flag`, `positional`, `positionals`, `subcommand`, `shell_completion_flag` macros.
- **ARGV parser**: long flags (`--foo val`, `--foo=val`), short flags (`-f val`), long-flag aliases, `--` separator.
- **Boolean flags**: auto-generates `--foo` and `--no-foo`; `negatable: false` opt to suppress.
- **Transformer chain**: per-type `__arg_transform`; user overrides via `transform_with:`. Union types require explicit `transform_with:`.
- **Validator chain**: per-type `__arg_validate`; user overrides via `validate_with:`. `range:`, `matches:`, `choices:` opts.
- **Auto-generated help**: `--help` / `-h` interception in dispatch; `hidden: true` opt to hide flags.
- **Positionals**: scalar `positional` + variadic `positionals` (at most one per command); leading/trailing combinations supported.
- **Subcommands**: routing and sub-subcommands; compile error when combined with positionals.
- **Enums**: case-name parsing (kebab-case-aware), `shortcut_flags: true` for `--<case>` shortcuts, `@[Flags]` comma-separated values.
- **Collections**: `Array(T)` with delimiter and accumulation, `Set(T)` with `set_operations:` for `+/-` prefixes, `Hash(String, T)` with `key=value` / `-key`.
- **Bundled type transformers**: `String`, all `Int*`/`UInt*`/`Float*` types, `Path`, `URI`, `Time`, `Log::Severity`, `Regex`.
- **Synthetic types**: `PositiveInt`, `NonNegativeInt`, `Percentage`, `EpochTime`, `Date`, `EnvVar`.
- **Shell completion**: bash, zsh, fish renderers + runtime `__complete` dispatcher with smart alias filtering and `@[Flags]` enum trailing-comma completion.
- **`--shell-completion <shell>`** install flag (configurable per-command via `shell_completion_flag`).

### Deferred to future releases

- POSIX-style boolean short-flag combining (`-abc` → `-a -b -c`).
- Path/File/Dir/EnvVar shell-native completion sentinels in generated scripts (file completion currently relies on the shell's own filename completion, not directed by the binary).
- `Symbol`-typed flags (Crystal's symbols are closed at compile time; use `String` + `choices:` instead).
- `Hash(String, T)` variadic positionals (variadic-only Array(T)/Set(T) for now).
- PowerShell, nushell, elvish renderers.
- Symlink-aware completion installation.
- Generated-script cache invalidation.
- `max:` enforcement on variadic positionals (implemented in 0.9.1).
