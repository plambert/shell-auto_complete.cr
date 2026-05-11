# Shell::AutoComplete — API Design

**Status:** Draft v1
**Date:** 2026-05-10
**Author:** Paul M. Lambert

## Goals

A Crystal shard for building command-line applications whose argument
parsing, `--help` output, and shell completion scripts (bash, zsh, fish)
all derive from a single source of truth: a high-level macro DSL that
defines commands and their parameters.

Dynamic completions — completions whose candidates depend on live state
(remote APIs, filesystem queries, prior flag values) — are first-class.
The generated shell scripts inline static structure for instant
completion and call back into the user's binary for dynamic positions.

## Non-goals

- PowerShell, nushell, elvish, or other shells beyond bash/zsh/fish.
- Configuration-file integration.
- Internationalization of help text.
- Short-flag aliases.
- Cross-flag constraints beyond enum-derived exclusive groups
  (e.g., "if `--foo` then `--bar` required").
- Combining short flags that take values (e.g., `-pPORT` where `-p`
  takes a value); basic boolean combining (`-abc`) is supported because
  stdlib `OptionParser` already does it.
- Driving real shells with `expect` in CI.
- Interop with an existing `OptionParser`-based CLI in v1.

## Top-level architecture

The user defines each (sub)command as a class via a `command` macro.
Inside the block, `flag` and `positional` macros declare parameters;
each expands to an annotated `property` whose declared type is the
return type of its transformer. A `subcommand` macro registers child
commands on a parent.

At compile time, `command` walks the class's instance variables and
their annotations to generate four artifacts:

1. A parser: `MyCommand.parse(argv : Array(String)) : MyCommand`
2. Help output: `MyCommand.help : String` (printed for `--help` / `-h`)
3. A completion dispatcher invoked when the binary receives a hidden
   `__complete` request from its own generated shell script.
4. Shell script renderers:
   `MyCommand.completion_script(:bash | :zsh | :fish) : String`.

`MyCommand.dispatch(ARGV)` is the entry point: it detects `__complete`
and `__completion <shell>` modes, otherwise parses ARGV and calls
`#run` on the populated instance.

## Macro DSL

### `command`

```crystal
command MyApp::Build, name: "build", description: "Build the project" do
  flag       ...
  positional ...
  subcommand ...

  def run
    # uses the populated @properties
  end
end
```

`command` opens (or defines) the given class as a subclass of
`Shell::AutoComplete::Command`, applies an internal
`@[Shell::AutoComplete::CommandDef(name:, description:)]` annotation,
and evaluates the block as the class body. The first argument must be
a constant path AST node; `name` and `description` are required.

Keyword arguments accepted on `command`:

- `name : String` (required) — the command word as it appears in the shell.
- `description : String` (required) — one-line summary for help.
- `header : String?` — text inserted above the options list in `--help`.
- `footer : String?` — text inserted below the options list in `--help`.
- `usage : String?` — custom usage line; default is generated.

### `flag`

Signature (conceptually):

```
flag <name> : <Type> [= <default>],
     <flag-strings>,   # array literal OR one or more string literals
     [<description>],  # first non-"-"-prefixed string literal (optional)
     **opts            # consumed by the macro or forwarded to validator
```

Examples:

```crystal
flag message : String?, %w(--message --msg -m), "Build message"

flag color : Bool = true, "--color", "-c", "Colorize output"

flag log_level : LogLevel = LogLevel::Info,
     "--log-level", "Log verbosity", expand_enum: true

flag perms : Perms = Perms::None,
     "--perms", "Granted permissions"   # @[Flags] enum, comma-separated

flag name : String?, "--name", "Build name",
     matches: /\A[a-z][a-z0-9-]*\z/

flag port : Int32?, "--port", "Port number", range: 1..65535

flag retries : Int32 = 3, "--retries", "-r", validate_with: :check_retries
```

Flag-string parsing (all entries must be string literals):

- The first `--`-prefixed string is the **canonical long flag**.
- Additional `--`-prefixed strings are **aliases** (parsed but
  optionally hidden from completion via `hide_aliases: true`).
- At most one `-`-prefixed single-letter string is the **short flag**.
- The first non-`-`-prefixed string is the **description**.

Reserved names: `--help` and `-h` may not be declared by user code;
attempting to do so is a compile error.

Recognized `flag` opts (consumed by the macro, not passed to the
validator):

- `expand_enum: true` (only valid for enum-typed properties; invalid
  for `@[Flags]` enums).
- `validate_with: :method_name` (overrides the validator lookup chain).
- `transform_with: :method_name` (overrides the transformer lookup
  chain).
- `hide_aliases: true` (omit non-canonical long flags from completion).
- `negatable: false` (Bool only; suppresses auto-generated `--no-foo`).
- `choices: %w[a b c]` — fixed list of acceptable values (also drives
  completion candidates and shell-side validation).
- `complete_with: :method_name` — dynamic completer for this flag's
  value; method receives a `CompletionContext` and returns
  `Array(String)` or `Array(Candidate)`.

All other keyword args (including `range:`, `matches:`, etc.) are
forwarded to the validator as `**kwargs`.

Path/File/Dir-typed flags and positionals automatically emit
shell-native file completion in the generated script (no
`complete_with:` needed). Explicit `complete_with:` overrides this.

### `positional`

```
positional <name> : <Type> [= <default>],
           <description>,
           **opts
```

Examples:

```crystal
positional name : String, "the build name"

positional files : Array(Path), "files to tag", min: 1

positional destination : Path, "destination"
```

The same transformer/validator chain applies. There are no flag-strings.
The declaration order in source = the binding order.

Recognized opts beyond those forwarded to the validator:

- `min: <Int>`, `max: <Int>` — bounds on a variadic positional
  (`Array(T)`, `Set(T)`, or `Hash(String, T)`). Defaults: `min: 0`,
  `max: Int32::MAX`.
- `complete_with: :method_name` — dynamic completer for this position.

### `subcommand`

```crystal
subcommand MyApp::Build
subcommand MyApp::Test
```

Registers a previously-defined command class as a child. Multiple
`subcommand` declarations may appear; order in source determines
display order in `--help`.

A command with subcommands may not also declare its own positionals.
(Flags on the parent are allowed and propagate to subcommands as
global flags.)

## Internal annotations (implementation detail)

- `Shell::AutoComplete::CommandDef`
- `Shell::AutoComplete::FlagDef`
- `Shell::AutoComplete::PositionalDef`

These are applied by the macro DSL; end users do not write them
directly. Named to avoid confusion with stdlib's `@[Flags]`.

## Type system: transformers and validators

Every flag and positional has a declared "input type" `T` (from the
macro) and a resolved property type `R` (the return type of `T`'s
transformer). `R` may equal `T`, or `T` may be a synthetic module that
maps to a different `R` (e.g., `PositiveInt` → `Int32`).

### Transformer lookup

For a parameter named `foo` declared with type `T`, the transformer is
looked up in this order; the first match wins:

1. Method `__arg_transform_foo(value : String)` defined on the command
   class.
2. Method `T.__arg_transform(value : String)` defined on the declared
   type.
3. Method `T.parse(value : String)` if it exists with that single-arg
   signature.

If none is found, compilation fails with a clear error pointing at the
declaration.

The transformer's return type is `R`. The generated property is
`property foo : R` (with default if supplied; the default must be
assignable to `R`).

`Bool`-typed parameters skip the transformer chain entirely; their
value is set directly from the flag form (`--foo` → `true`,
`--no-foo` → `false`).

### Validator lookup (optional)

For a parameter named `foo` declared with type `T`, the validator is
looked up in this order; the first match wins:

1. Method `__arg_validate_foo(value, **kwargs)` on the command class.
2. Method `T.__arg_validate(value, **kwargs)` on the declared type.

If `validate_with: :symbol` was given on the macro, that method is
used directly, bypassing the lookup chain.

If none is found, validation is skipped.

Validator signature:

```crystal
def __arg_validate_foo(value : R, **kwargs) : Bool | String
end
```

- `value` is the transformer's output.
- `**kwargs` is the flag-macro's keyword args minus those consumed by
  the macro itself (`expand_enum`, `validate_with`, `transform_with`,
  `hide_aliases`, `negatable`, `min`, `max`, `complete_with`).
- Return `true` → accept.
- Return a `String` → raise `ArgumentError.new(string)`.
- Return `false` → raise `ArgumentError.new("not a valid <name>")`.
- Raising `ArgumentError` directly is also supported.

`Bool`-typed parameters skip the validator chain.

### Bundled transformers

Shipped with the shard:

- Scalars: `Int8`, `Int16`, `Int32`, `Int64`, `UInt8`, `UInt16`,
  `UInt32`, `UInt64`, `Float32`, `Float64`, `String`, `Char`, `Symbol`.
- `Bool` is handled by the macro layer, not via a transformer.
- Stdlib types: `URI`, `Path`, `File` (returns `Path`, validates
  existence), `Dir` (returns `Path`, validates existence), `Time`
  (ISO 8601 + RFC 3339 + common formats), `Socket::IPAddress`,
  `Log::Severity`, `Regex`.
- Collections: `Array(T)`, `Set(T)`, `Hash(String, T)` — see below.
- Enums (any user-defined enum): match enum case names, kebab-cased.
  For `@[Flags]` enums, accept comma-separated lists via `Enum.parse`.

### Synthetic types

Synthetic types are modules (not classes) that define
`__arg_transform` and optionally `__arg_validate`. The property's
resolved type is the transformer's return type; the synthetic module
name is never referenced at runtime by the property.

Shipped synthetic types:

- `Shell::AutoComplete::Types::PositiveInt` → `Int32`, requires `> 0`.
- `Shell::AutoComplete::Types::NonNegativeInt` → `Int32`, requires `>= 0`.
- `Shell::AutoComplete::Types::Percentage` → `Float64`, requires `0.0..100.0`.
- `Shell::AutoComplete::Types::EpochTime` → `Time`, parses float seconds.
- `Shell::AutoComplete::Types::Date` → `Time`, accepts `YYYY-MM-DD`.

User-defined synthetic types follow the same pattern.

Numeric scalar types (`Int*`, `Float*`) also honor a `range:` kwarg in
their built-in validator: `flag port : Int32?, "--port", range: 1..65535`
validates without requiring a custom method.

### Collections

#### `Array(T)`

- Multiple occurrences on the command line append:
  `--tag a --tag b` → `["a", "b"]`.
- A single occurrence splits on `,`:
  `--tag a,b` → `["a", "b"]`.
- Per-element transformation via `T`'s transformer chain (except
  `Array(String)`, which skips per-element transform).

#### `Set(T)`

Same as `Array(T)` but with per-element sigils:

- No prefix or `+` prefix → add to set.
- `-` prefix → remove from set.

`--levels +debug --levels -info,+warn` accumulates as expected.

#### `Hash(String, T)`

- Per occurrence, match against `\A(?<key>[A-Za-z0-9_+]+)=(?<value>.*)\z`
  to set; transform value through `T`'s chain.
- Match against `\A-(?<key>[A-Za-z0-9_-]+)\z` to delete a key.

Keys are restricted to `String`. Users who need richer keys should
write a custom transformer.

### Nillability

If a parameter's resolved type `R` is nillable (`R = T | Nil`) and the
flag is invoked with an empty string (`--foo=""`), the property is set
to `nil`. Exception: if `R` is `String?`, the empty string passes
through to satisfy `R`.

If a parameter has no default value and its resolved type is
non-nillable, the parameter is **required**; omitting it from ARGV is
a parse error.

### Enums

- Ordinary enums: parser accepts case-insensitive case names with
  underscores or hyphens. Completion candidates are the kebab-cased
  case names.
- `@[Flags]` enums: parser accepts comma-separated lists of case names
  via `Enum.parse`. Completion candidates are individual case names
  (the shell user composes the comma-separated value themselves; full
  combinatorial completion is out of scope).
- `expand_enum: true` is valid only on ordinary enums; on `@[Flags]`
  enums it is a compile error.

## Boolean flags

A flag whose property type is `Bool`:

- Auto-generates `--foo` and `--no-foo`. Both appear in completion.
- Short flags get no auto-complement (`-c` does not imply `-C`).
- Setting `negatable: false` on the macro suppresses `--no-foo`.

## Enum-derived exclusive groups

With `expand_enum: true` on an ordinary-enum flag:

- The canonical `--flag <case>` form is generated, with completion
  candidates drawn from the enum cases.
- One shortcut flag per enum case is generated, kebab-cased
  (`LogLevel::Debug` → `--debug`). All shortcuts target the same
  property; **last one wins** if multiple are passed (no error,
  no warning).

## Positional binding algorithm

After flag parsing finishes (including `--` handling), let:

- `positionals` = declared positionals in source order, partitioned
  into `leading` (scalars before the variadic), `variadic` (at most one),
  and `trailing` (scalars after the variadic).
- `tokens` = the list of unconsumed tokens.

Binding rules:

1. The macro layer enforces **at most one variadic positional** per
   command. Violation is a compile error.
2. Required scalars must be present. `M = tokens.size`, `L =
   leading.size`, `R = trailing.size`. If `M < L + R`, parse error
   ("expected at least N positional args, got M").
3. Leading scalars bind to `tokens[0..L-1]`.
4. Trailing scalars bind to `tokens[M-R..M-1]`.
5. Variadic gets `tokens[L..M-R-1]` (possibly empty). Its `min:`/`max:`
   bounds are then checked.
6. If there is no variadic, `M` must equal `L + R` plus the number of
   trailing optionals satisfied (left to right). Extra tokens → parse
   error.
7. Optional scalar positionals (nillable type) are allowed only at
   the trailing end of the declaration list and only when there is no
   variadic. Other placements are a compile error.

### Cases (declared → ARGV → binding)

`[name(req), files(*)]`:
- `tag` → parse error (need at least 1 token)
- `tag alpha` → name=`"alpha"`, files=`[]`
- `tag alpha a.txt b.txt` → name=`"alpha"`, files=`[Path("a.txt"), Path("b.txt")]`

`[files(* min:1), destination(req)]`:
- `mv dest` → parse error (variadic requires min=1, but with `L=0,R=1,M=1`
  the variadic gets `[]`)
- `mv a.txt dest` → files=`[Path("a.txt")]`, destination=`Path("dest")`

`[name(req), files(*), destination(req)]`:
- `stage a dest` → name=`"a"`, files=`[]`, destination=`Path("dest")`
- `stage a x y dest` → name=`"a"`, files=`[Path("x"), Path("y")]`,
  destination=`Path("dest")`
- `stage a` → parse error (need at least 2 tokens)

## `--` semantics

The token `--`, when seen during flag parsing, terminates flag parsing.
All remaining tokens are treated as positional and are bound by the
algorithm above. To collect arbitrary post-`--` tokens verbatim, declare
a trailing `Array(String)` variadic.

## Help generation

Auto-generated from the macro DSL. `--help` and `-h` are reserved and
intercepted by `dispatch` before any other parsing.

Format:

```
<custom header, if any>

Usage: <custom usage or auto-generated>

<description>

Subcommands (if any):
  <name>    <description>
  ...

Options:
  --flag, --alias, -f VALUE   <description>
  ...

Positional arguments:
  <name>    <description>
  ...

<custom footer, if any>
```

Help formatting is opinionated; only `header`, `footer`, and `usage`
are configurable on `command` in v1.

## Completion script generation

Each command class exposes:

```crystal
MyCli.completion_script(:bash) : String
MyCli.completion_script(:zsh)  : String
MyCli.completion_script(:fish) : String
```

These return the full script as a `String`. `dispatch` provides a
built-in `__completion <shell>` mode that prints the script to stdout
for installation:

```
mycli __completion bash > /etc/bash_completion.d/mycli
```

The generated script inlines all **static** structure:

- Subcommand names and descriptions.
- Long-flag forms (canonical + aliases unless `hide_aliases:`).
- Short flags.
- `--no-*` complements for Bool flags.
- Enum case names for `expand_enum:` flags.
- Fixed `choices:` lists.

It defers **dynamic** positions to a runtime callback:

- Any flag value with a `complete_with:` method.
- Any positional with a `complete_with:` method.
- Path / File / Dir typed values (fall back to shell-native file
  completion).

Generated bash callback shape:

```bash
_mycli() {
  local out
  out=$(mycli __complete "$COMP_CWORD" "${COMP_WORDS[@]}")
  COMPREPLY=( $(compgen -W "$out" -- "${COMP_WORDS[COMP_CWORD]}") )
}
complete -F _mycli mycli
```

Zsh and fish renderers use richer descriptors so each candidate shows
its description.

## Runtime completion dispatch

`MyCli.dispatch(argv)` detects `__complete <cword> <words...>` and:

1. Parses `words` up to but not including the active token, applying
   flag and positional rules in a permissive mode (no required-arg
   errors, unresolved transformers downgraded to passthrough).
2. Determines which slot the cursor is in (which flag's value, which
   positional position, or "expecting a flag/subcommand").
3. Invokes the appropriate `complete_with:` method on a fresh instance
   of the partially-populated command class (so the method can see
   prior `@flag_values`).
4. Prints candidates to stdout, one per line, optionally with
   tab-separated descriptions.

## Shell support

Bash, zsh, fish — equal priority. The same metadata drives three
renderers; renderer differences are confined to formatting.

## Testing strategy

- **Golden-file specs** per renderer: a small set of representative
  command trees produce expected bash/zsh/fish output. Regenerating
  the goldens is a single `crystal spec --regenerate-goldens` task.
- **Synthetic `CompletionContext` specs**: unit-test the dispatcher's
  slot-detection logic by constructing contexts directly.
- **Parser specs**: table-driven (ARGV → expected populated instance
  or expected `ArgumentError`).
- **Transformer/validator unit specs**: per-type roundtrip.
- No `expect`-based integration tests.

## File layout (proposed)

```
src/
  shell-auto_complete.cr            # entry point, requires below
  shell-auto_complete/
    command.cr                       # base class, dispatch, parse
    macros/
      command.cr                     # command, subcommand macros
      flag.cr                        # flag macro + parsing
      positional.cr                  # positional macro + binding
    transformers/
      scalar.cr
      collection.cr
      stdlib.cr                      # URI, Path, Time, ...
      enum.cr
    types/
      positive_int.cr
      percentage.cr
      epoch_time.cr
      date.cr
    completion/
      context.cr
      dispatcher.cr
      renderer.cr                    # shared rendering helpers
      bash.cr
      zsh.cr
      fish.cr
    help.cr
spec/
  ...mirrors src/ layout...
specs/
  2026-05-10-shell-autocomplete-api-design.md     # this file
```

## Open questions (deferred to implementation)

- Whether the macro layer should run a basic completeness check at
  compile time (warn on commands with no subcommands and no
  positionals/flags).
- Exact shell-script behavior when `mycli` is invoked via an alias or
  symlink — does completion follow the alias?
- Cache invalidation for the completion script (re-installing after
  the binary changes).

These are implementation decisions, not API decisions.
