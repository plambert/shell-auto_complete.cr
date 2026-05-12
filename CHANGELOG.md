# Changelog

All notable changes are documented here.

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
