# Changelog

All notable changes are documented here.

## [2.0.0] - 2026-06-12

Major release closing issues #9–#22. Three breaking changes, marked below: required `delimiter:` on collection flags, unconsumed extra string literals as compile errors, and routing-behavior changes around subcommands. Everything else is additive.

### Added (flag inheritance, #22)

- Parent-level flag inheritance: `parent: SomeCommand` on the `command` macro makes the new command inherit every flag the parent declares — properties, parsing, `flag_given?`, and completion all see them, and help renders them under an `Inherited options` heading. Inheritance composes with (but is independent of) `subcommand` routing, and chains through multiple levels. Collisions between an inherited flag and a leaf flag follow #10's rules: compile error by default, `override: true` to replace at the leaf (freeing all of the inherited flag's spellings).
- Routing commands can carry their own flags. `dispatch` now walks argv past the command's own flags (and the values they consume) to find the subcommand word, so shared flags work before or after it (`app --verbose scan` and `app scan --verbose` both parse), and `app --init` with subcommands present parses `--init` instead of raising `unknown subcommand: --init`. Tokens after `--` never route. Shell completion descends past interleaved flags the same way.

### Changed

- **BREAKING**: with subcommands present, an unknown dash token before the subcommand word is now `unknown flag: --x` (previously `unknown subcommand: --x`), and an unknown subcommand word is rejected even when `--help` appears later on the line (previously the `--help` intercept won and printed the root's help). (#22)
- The `--help`, `-h`, and `--all-help` intercepts in `dispatch` now stop at the `--` terminator, consistent with the parser: a literal `--help` after `--` is a positional value, not a help request. (#21)
- **BREAKING**: `delimiter:` is now a required choice on `Array(T)` and `Set(T)` flags — `","` (split each value) or `nil` (each occurrence is one element). Omitting it is a compile error. Previously every collection flag silently split on `,`, which corrupts values whose data legally contains commas (paths, regexes, URLs, titles) — the unsafe choice was the implicit one. `Hash(String, T)` flags are unaffected (no splitting happens there). Migration: add `delimiter: ","` to keep the old behavior. (#17)

### Added

- Help layout hooks: `help_sections:` on `command` reorders (or omits) the middle help sections — any subset of `:description`, `:options`, `:subcommands`, `:positionals` (header/usage always lead, footer always trails). `group: "Heading"` on `flag` renders the flag under its own heading after the ungrouped options; `ordered_flag_group` members render under their group's description heading automatically. (#21)
- `immediate:` on switch flags, for `--list-formats`-style print-reference-data-and-exit flags: dispatch invokes the designated handler as soon as the spelling appears before `--`, regardless of whether the rest of the line validates — like their callback-parser ancestors. `immediate: :method_name` names the handler; `immediate: true` uses the `immediate_<flag>` convention. Only valid on `Bool`/`Bool?` flags. (#21)
- Hash flag keys may now contain dots and colons (`a.b=1`, `log:level=debug`); the key charset lives in one place (`Shell::AutoComplete::HashFlag`) and the `-key` delete pattern is derived from it, so the two cannot drift. `hash_operations: false` disables the bare `-key` delete form on flags where deletion is meaningless, turning a `-foo` typo of `foo=...` into a loud parse error (mirroring `set_operations:`); using it on a non-Hash flag is a compile error. The `-foo=bar` middle case now gets a targeted error suggesting both readings: `use foo=bar to assign, or -foo to delete`. (#20)
- Value flags render a placeholder (metavar) in help — `--port PORT` instead of `--port` — so users can tell which flags take a value and what shape it is. Three input forms: a positional all-caps string before the description (`flag port : Int32, "--port", "PORT", "Server port"`; punctuation like `SRC:DST` and `NAME=VALUE` allowed), a placeholder embedded in the flag string callback-parser style (`"--after TIME"`), and a `placeholder:` named option for shapes the heuristics can't express (`HOST[:port]`). When none is given, the placeholder derives from the declared type: `NUMBER`, `FLOAT`, `TEXT`, `PATH`/`FILE`/`DIR`, `URL`, `TIME`, `DATE`, `REGEX`, `CHAR`, `KEY=VALUE` for Hash flags, pipe-joined values for small enums and `choices:` sets (`asc|desc`), the upcased type name for large enums, and `VALUE` as the final fallback. Switches get none (an explicit placeholder on a switch is a compile error). (#19)
- **BREAKING**: an unconsumed extra string literal in a `flag` declaration is now a compile error instead of being silently dropped — this catches typos and is what makes the positional placeholder form safe. (#19)
- Descriptions, headers, and footers accept constant references and method references, so help text can mirror the runtime constants that drive validation (`flag preset : String?, "--preset", PRESET_HELP, choices: PRESETS`). Constants resolve at macro-expansion time when they are plain string literals; computed constants and method references resolve at help-render time (method references call a class method of the command). `flag`, `positional`, and `positionals` also accept `description:` as a named option — the reliable spelling when the description directly follows the type declaration, where Crystal's parser reads a bare constant as a type. (#18)
- `transform_with:`/`validate_with:` and the per-flag `__arg_transform_<name>`/`__arg_validate_<name>` method conventions are now honored per element on `Array(T)`, `Set(T)`, and `Hash(String, T)` flags, with the same dispatch precedence as scalar flags. Element types without a stock transformer (e.g. `Tuple(String, String)` for a `SRC:DST` flag) become declarable, and a malformed item is rejected at parse time with the flag's name in the error (`--map: expected SRC:DST, got "nope"`); `ArgumentError` from a custom transform converts to `ParseError` the same way. Set-operation payloads transform after the `+`/`-` prefix is stripped; deletes skip validation (the value only needs to parse to be compared). (#16)

- `ordered_flag_group` macro: declares a group of value-taking long options whose occurrences are delivered, in command-line order, to a block — the rsync/tar `--include`/`--exclude` shape, where interleaving between spellings is the semantics. The block runs at parse time on the fresh instance, once per occurrence, with the matched key (dashes stripped) and raw value; an `ArgumentError` raised from it converts to a clean `ParseError` carrying the matched spelling, giving parse-time per-item validation. Members render in help with per-spelling descriptions, complete like any flag, participate in the duplicate-name checker, and appear in `parsed_occurrences`. Value-taking members only in this first version; switch members are deferred. (#15)

- `shortcut_flags:` accepts a configuration named tuple alongside the bare `true`: `only:`/`except:` filter which enum cases get generated switches (mutually exclusive; unknown case names are compile errors), and `aliases:` adds switches that force a specific case (`shortcut_flags: {except: [:none], aliases: {quiet: :warn, verbose: :info}}`). Alias switches feed the same flag's value stream, so `--quiet --debug` resolves last-wins against real shortcuts with no extra machinery; they count toward `flag_given?`, register in the duplicate-name checker, complete, and render in help as `Alias for --log-level warn`. (#14)

- `Bool?` flags now parse as tri-state switches: `--x` → `true`, `--no-x` → `false`, untouched → `nil`. Previously `Bool?` fell into the value-taking branch and demanded an argument. This is the missing primitive for mutation-style CLIs and config-file layering, where a file default applies only to options the user did not set. (#12)
- `flag_given?(:name)` on every command instance: whether the named flag (by declaration name) was explicitly given under any of its spellings — canonical, aliases, short form, generated `--no-` negations, and enum shortcut switches. Distinguishes an explicit `--no-organized` (or an explicit value equal to the default) from silence. Unknown names raise `ArgumentError`. (#12)
- Long aliases on Bool/`Bool?` switches now work. Previously `flag dryrun : Bool, "--dryrun", "--dry-run", ...` silently left `--dry-run` (and `--no-dry-run`) as unknown flags; aliases were accepted by the macro but never matched at parse time. Every declared long alias now parses, gets its own generated `--no-` negation, appears in completion, and registers in the duplicate-name checker. (#13)

- `parsed_occurrences` on every command instance: a raw, ordered log of each flag occurrence matched during parse, as `Array({String, String?})` — the spelling exactly as typed (dashes kept, aliases not canonicalized) and the raw value consumed from argv or after `=` (`nil` for switches and forced-value shortcut flags). Positionals are not logged; unknown flags never appear (parse rejects them first). Enables audit logging, re-emitting an equivalent command line, and order-sensitive resolution in `run`. (#11)

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
