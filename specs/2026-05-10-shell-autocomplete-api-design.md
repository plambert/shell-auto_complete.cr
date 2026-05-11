# Shell::AutoComplete — API Design

**Status:** Draft v2
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
Inside the block, `flag`, `positional`, and `positionals` macros
declare parameters; each expands to an annotated `property` whose
declared type is the return type of its transformer. A `subcommand`
macro registers child commands on a parent. Subcommands may
themselves have subcommands.

At compile time, `command` walks the class's instance variables and
their annotations to generate four artifacts:

1. A parser: `MyCommand.parse(argv : Array(String)) : MyCommand`
2. Help output: `MyCommand.help : String` (printed for `--help` / `-h`)
3. A completion dispatcher invoked when the binary is asked to emit
   completion candidates at runtime.
4. Shell script renderers:
   `MyCommand.completion_script(:bash | :zsh | :fish) : String`.

`MyCommand.dispatch(ARGV)` is the entry point. Before normal parsing
it checks for, in order:

1. The shell-completion install flag (default `--shell-completion`,
   customizable via `shell_completion_flag` macro). Emits the script
   to STDOUT (or an install example to STDERR, if STDOUT is a tty).
2. The hidden runtime-completion form (used by the generated shell
   script). Emits candidates to STDOUT.
3. `--help` / `-h`. Emits help text and exits.

If none match, ARGV is parsed normally and `#run` is called on the
populated instance.

## Completion data types

```crystal
struct Shell::AutoComplete::Candidate
  getter value : String
  getter description : String?
end
```

Completers may return `Array(String)` (no descriptions) or
`Array(Candidate)`. The bash renderer ignores descriptions; zsh and
fish use them to annotate candidates in the menu.

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
a constant path AST node.

Keyword arguments accepted on `command`:

- `name : String?` — the command word as it appears in the shell.
  On the top-level command (the one passed to `dispatch`), `name`
  defaults to `File.basename(PROGRAM_NAME)`. On subcommands, `name`
  is required.
- `description : String` (required) — one-line summary for help.
- `header : String?` — text inserted above the options list in `--help`.
- `footer : String?` — text inserted below the options list in `--help`.
- `usage : String?` — custom usage line; default is generated.

Two additional macros may appear at the top of any `command` block to
adjust framework-level behavior:

- `shell_completion_flag "--foo"` — overrides the default
  `--shell-completion` install flag.
- (Future hook points may be added here as needed.)

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
     "--log-level", "Log verbosity", shortcut_flags: true

flag perms : Perms = Perms::None,
     "--perms", "Granted permissions"   # @[Flags] enum, comma-separated

flag name : String?, "--name", "Build name",
     matches: /\A[a-z][a-z0-9-]*\z/

flag port : Int32?, "--port", "Port number", range: 1..65535

flag retries : Int32 = 3, "--retries", "-r", validate_with: :check_retries
```

Flag-string parsing (all entries must be string literals):

- The first `--`-prefixed string is the **canonical long flag**.
- Additional `--`-prefixed strings are **aliases**. They are accepted
  by the parser. In completion output, an alias is shown only when
  the current word prefix-matches the alias but not the canonical
  (see Runtime completion dispatch).
- At most one `-`-prefixed single-letter string is the **short flag**.
- The first non-`-`-prefixed string is the **description**.

Reserved names: `--help`, `-h`, and the configured shell-completion
flag (default `--shell-completion`) may not be declared by user code;
attempting to do so is a compile error.

Recognized `flag` opts (consumed by the macro, never forwarded):

- `shortcut_flags: true` — only valid on ordinary-enum properties.
  Generates one `--<case>` shortcut flag per enum case in addition
  to the canonical `--<flag> <case>` form (e.g., `LogLevel::Debug`
  produces `--debug`). Invalid for `@[Flags]` enums; compile error.
- `validate_with: :method_name` — overrides the validator lookup chain.
- `transform_with: :method_name` — overrides the transformer lookup chain.
  **Required** when the property type is a union (e.g., `String | Int32`);
  compile error otherwise.
- `complete_with: :method_name` — overrides the completer lookup chain
  with a method on the class receiving a `CompletionContext` and
  returning `Array(String)` or `Array(Candidate)`.
- `negatable: false` (Bool only; suppresses auto-generated `--no-foo`).
- `hidden: true` — omit from both `--help` and completion output.

All other keyword args (e.g., `range:`, `matches:`, `choices:`,
`delimiter:`, `set_operations:`) are filtered at macro-expansion
time so consumed opts are removed, then forwarded to the transformer,
validator, and completer as `**opts`.

Path/File/Dir/EnvVar-typed flags and positionals automatically emit
shell-native completion in the generated script (no `complete_with:`
needed). Explicit `complete_with:` overrides this.

### `positional` (scalar) and `positionals` (variadic)

```
positional  <name> : <Type> [= <default>], <description>, **opts
positionals <name> : <Collection-Type>,     <description>, **opts
```

Examples:

```crystal
positional  name        : String,       "the build name"
positionals files       : Array(Path),  "files to tag", min: 1
positional  destination : Path,         "destination"
```

`positional` declares a scalar positional argument. `positionals`
declares the (at most one) variadic, whose type must be `Array(T)`,
`Set(T)`, or `Hash(String, T)`. Splitting the two macros makes the
intent explicit and lets each enforce its own constraints at compile
time:

- Declaring `positionals` more than once in a single `command` is a
  compile error.
- Declaring `positional` with a collection type, or `positionals`
  with a non-collection type, is a compile error.
- A `command` block that has any `subcommand` declarations may not
  declare any positionals.

The same transformer/validator/completer chains apply. Declaration
order in source determines binding order.

Recognized macro-consumed opts:

- `min: <Int>`, `max: <Int>` — bounds on the count of values bound to
  a `positionals` declaration. Defaults: `min: 0`, `max: Int32::MAX`.
  Not valid on `positional`.
- `complete_with: :method_name` — dynamic completer for this position.
- `hidden: true` — omit from `--help` (positionals are not directly
  completed by name, so this only affects help).

All other keyword args are forwarded to the type's transformer,
validator, and completer.

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
- `Shell::AutoComplete::PositionalDef`   — for scalar positionals
- `Shell::AutoComplete::PositionalsDef`  — for the variadic positional

These are applied by the macro DSL; end users do not write them
directly. Named to avoid confusion with stdlib's `@[Flags]`.

## Type system: transformers, validators, and completers

Every flag and positional has a declared "input type" `T` (from the
macro) and a resolved property type `R` (the return type of `T`'s
transformer). `R` may equal `T`, or `T` may be a synthetic module that
maps to a different `R` (e.g., `PositiveInt` → `Int32`).

Three parallel hook chains run against the type system: transformer
(string → value), validator (value → ok/error), and completer (prefix
→ candidates). All three receive the same filtered `**opts` namedtuple
(the macro-consumed keys are stripped at compile time).

Union types (e.g., `String | Int32`) are allowed **only** when
`transform_with:` is provided on the macro. The macro otherwise emits
a compile error pointing at the declaration.

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

1. Method `__arg_validate_foo(value, **opts)` on the command class.
2. Method `T.__arg_validate(value, **opts)` on the declared type.

If `validate_with: :symbol` was given on the macro, that method is
used directly, bypassing the lookup chain.

If none is found, validation is skipped.

Validator signature:

```crystal
def __arg_validate_foo(value : R, **opts) : Bool | String
end
```

- `value` is the transformer's output.
- `**opts` is the flag-macro's keyword args minus those consumed by
  the macro itself (`shortcut_flags`, `validate_with`, `transform_with`,
  `complete_with`, `negatable`, `hidden`, and on positionals
  additionally `min`, `max`). The filter is applied at compile time;
  validators do not see consumed keys.
- Return `true` → accept.
- Return a `String` → raise `ArgumentError.new(string)`.
- Return `false` → raise `ArgumentError.new("not a valid <name>")`.
- Raising `ArgumentError` directly is also supported.

`Bool`-typed parameters skip the validator chain.

### Completer lookup (optional)

For a parameter named `foo` declared with type `T`, the completer is
looked up in this order; the first match wins:

1. Method `__arg_complete_foo(prefix : String, **opts)` on the command
   class. This method may use `@field`-style access to other
   already-parsed values for context.
2. Method `T.__arg_complete(prefix : String, **opts)` on the declared
   type.

If `complete_with: :symbol` was given on the macro, that method is
used directly, bypassing the lookup chain. If none is found,
completion returns an empty list (the position contributes no
candidates beyond what the parent context provides — e.g., file
completion for `Path`).

Completer signature:

```crystal
def __arg_complete_foo(prefix : String, **opts) : Array(String) | Array(Candidate)
end
```

The shell renderers may emit "file-completion" or "envvar-completion"
sentinels rather than a concrete list, so the result type also admits
those sentinel values via a small ADT used internally by the renderer.
At the user-facing level only `Array(String)` and `Array(Candidate)`
need to be considered.

Default `__arg_complete` implementations shipped with the shard:

- `String` — reads `choices:` from `**opts`; emits a kebab-case-aware
  prefix-filtered subset if present, otherwise no candidates.
- Numeric scalars (`Int*`, `Float*`) — no candidates by default. Range
  validation does not enumerate candidates.
- `Bool` — handled by the macro layer; not invoked at runtime.
- Ordinary enums — case names, kebab-cased.
- `@[Flags]` enums — case names. The completer is also aware of the
  active prefix and offers the cases not already present in the
  comma-separated value (e.g., `--perms read,` offers `write,execute`).
- `Path`, `File`, `Dir` — emit shell-native file-completion sentinel.
- `Shell::AutoComplete::Types::EnvVar` — emit shell-native
  environment-variable-completion sentinel.
- Collections — delegate to the element type's `__arg_complete` with
  awareness of the active partial value (split on the active
  `delimiter`).

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
  `String`'s element transformer is a no-op (no special casing of
  `Array(String)` is needed).
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
- `Shell::AutoComplete::Types::EnvVar` → `String`, accepts only valid
  environment-variable names (`^[A-Za-z_][A-Za-z0-9_]*$`); emits
  shell-native environment-variable completion.

User-defined synthetic types follow the same pattern.

Numeric scalar types (`Int*`, `Float*`) also honor a `range:` kwarg in
their built-in validator: `flag port : Int32?, "--port", range: 1..65535`
validates without requiring a custom method.

### Collections

All collection transformers honor a `delimiter:` kwarg.

- `delimiter: ","` (default) — each occurrence's value is split on the
  delimiter; every resulting element is run through `T`'s transformer
  chain.
- `delimiter: ";"` (or any other `String`) — split on that string.
- `delimiter: nil` — no splitting; the entire occurrence is treated
  as a single element (passed through `T`'s transformer verbatim).

Multiple occurrences on the command line always accumulate, regardless
of `delimiter:`.

#### `Array(T)`

- `--tag a --tag b` → `["a", "b"]`
- `--tag a,b` → `["a", "b"]` (default delimiter)
- `--tag a,b --tag c` → `["a", "b", "c"]`
- With `delimiter: nil`: `--tag a,b` → `["a,b"]`.

#### `Set(T)`

By default, `Set(T)` behaves like `Array(T)` with deduplication —
no prefix interpretation.

With `set_operations: true`, per-element sigils are recognized:

- No prefix or `+` prefix → add to set.
- `-` prefix → remove that element from the set.

`flag levels : Set(LogLevel), "--levels", set_operations: true`
makes `--levels +debug --levels -info,+warn` work as expected.

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
  underscores or hyphens. Completion candidates (via
  `Enum.__arg_complete`) are the kebab-cased case names.
- `@[Flags]` enums: parser accepts comma-separated lists of case names
  via `Enum.parse`. The completer is aware of the active partial value
  and, when the cursor is after a trailing `,`, offers only the cases
  not already present in the comma-separated value.
- `shortcut_flags: true` is valid only on ordinary enums; on `@[Flags]`
  enums it is a compile error.

## Boolean flags

A flag whose property type is `Bool`:

- Auto-generates `--foo` and `--no-foo`. Both appear in completion.
- Short flags get no auto-complement (`-c` does not imply `-C`).
- Setting `negatable: false` on the macro suppresses `--no-foo`.

## Enum-derived exclusive groups (`shortcut_flags`)

With `shortcut_flags: true` on an ordinary-enum flag:

- The canonical `--flag <case>` form is generated. Completion
  candidates for the value come from the enum's `__arg_complete`.
- One shortcut flag per enum case is generated, kebab-cased
  (`LogLevel::Debug` → `--debug`). All shortcuts target the same
  property; **last one wins** if multiple are passed (no error,
  no warning).

## Positional binding algorithm

After flag parsing finishes (including `--` handling), let:

- `leading` = `positional` declarations before any `positionals`
  declaration.
- `variadic` = the (at most one) `positionals` declaration, with its
  `min:`/`max:` bounds.
- `trailing` = `positional` declarations after the `positionals`
  declaration.
- `tokens` = the list of unconsumed tokens.

Binding rules:

1. At most one `positionals` declaration per command (compile error
   otherwise).
2. Optional scalar positionals (nillable type) are allowed only at the
   trailing end of the declaration list and only when there is no
   `positionals`. Other placements are a compile error.
3. Pre-check: `tokens.size >= leading.size + variadic.min + trailing.size`.
   Otherwise parse error ("expected at least N positional args,
   got M").
4. Implementation pattern (generated per command):

   ```crystal
   def bind_positionals(args : Array(String))
     stack = args.dup
     # leading scalars
     name = stack.shift? || raise ArgumentError.new("missing <name>")
     # variadic
     while stack.size > {{ trailing.size }}
       files << stack.shift
     end
     # trailing scalars
     destination = stack.shift? || raise ArgumentError.new("missing <destination>")
     raise ArgumentError.new("too many positional args") unless stack.empty?
     # transformers/validators run next, populating the instance
   end
   ```

5. After binding, the variadic's `min:` and `max:` bounds are checked.
6. Per-element transformers run on the variadic's contents and on each
   scalar's bound token, then validators run.

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
are configurable on `command` in v1. Flags or positionals declared
with `hidden: true` are omitted from help.

## Completion script generation and installation

Each command class exposes:

```crystal
MyCli.completion_script(:bash) : String
MyCli.completion_script(:zsh)  : String
MyCli.completion_script(:fish) : String
```

These return the full script as a `String`. They are also reachable
through the install flag (default `--shell-completion`, customizable
via `shell_completion_flag "--foo"` inside the top-level `command`
block).

Install-flag behavior, in `dispatch`:

1. If `ARGV[0]` is the install flag:
   1. If `ARGV[1]` is missing or not a recognized shell name, write
      to STDERR the list of supported shells plus an example
      installation command, and exit with status 1.
   2. Otherwise, if STDOUT is a tty, write to STDERR a recommended
      installation command (e.g.,
      `eval "$(mycli --shell-completion bash)"`) and exit with status 1.
      This prevents accidentally dumping shell code into a terminal.
   3. Otherwise, write the completion script to STDOUT and exit 0.

Sample install incantation:

```sh
eval "$(mycli --shell-completion bash)"            # interactive shell
mycli --shell-completion bash > /etc/bash_completion.d/mycli   # system-wide
```

### What gets inlined vs called back

The generated script inlines all **static** structure:

- Subcommand names and descriptions.
- Canonical long flags, short flags, `--no-*` complements for Bool
  flags.
- Aliases (included; smart visibility happens at the runtime
  callback, see Runtime completion dispatch).
- Enum case names for `shortcut_flags:` flags.
- Fixed `choices:` lists when statically present.

It defers to a runtime callback for:

- Any flag value or positional with `complete_with:` (explicit) or
  whose type's `__arg_complete` is non-trivial.
- Smart alias filtering whenever a flag has aliases.
- `@[Flags]` enum trailing-comma completion.
- Path/File/Dir/EnvVar — emitted as shell-native sentinels (which the
  shell handles directly without calling back).

Generated bash callback shape:

```bash
_mycli() {
  local out
  out=$(mycli __complete "$COMP_CWORD" "${COMP_WORDS[@]}")
  COMPREPLY=( $(compgen -W "$out" -- "${COMP_WORDS[COMP_CWORD]}") )
}
complete -F _mycli mycli
```

The hidden `__complete` form on the binary is an implementation
detail used only by the generated shell scripts; it is not part of
the user-facing CLI surface.

Zsh and fish renderers use richer descriptors so each candidate shows
its description (from `Candidate#description`).

## Runtime completion dispatch

`MyCli.dispatch(argv)` detects `__complete <cword> <words...>` and:

1. Parses `words` up to but not including the active token, applying
   flag and positional rules in a permissive mode (no required-arg
   errors, unresolved transformers downgraded to passthrough).
2. Determines which slot the cursor is in (which flag's value, which
   positional position, or "expecting a flag/subcommand").
3. Builds the candidate list:
   - When completing a flag name, expand all canonical long flags
     plus their aliases. Filter against `COMP_WORDS[COMP_CWORD]`:
     if any canonical form prefix-matches the active word, hide all
     of that flag's aliases from the output; otherwise include any
     alias that does prefix-match. Hidden flags (`hidden: true`)
     are excluded outright.
   - When completing a flag value or positional, look up the
     completer chain (overridden by `complete_with:`) and invoke it
     against a fresh instance of the partially-populated command
     class so the method can read `@flag_values`.
   - For `@[Flags]` enum values, if the active partial value ends
     with `,`, offer only cases not already present.
4. Prints candidates to stdout, one per line. Zsh/fish renderers
   include tab-separated descriptions when the completer returns
   `Array(Candidate)`.

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
    candidate.cr                     # Candidate struct
    macros/
      command.cr                     # command, subcommand, shell_completion_flag
      flag.cr                        # flag macro + parsing
      positional.cr                  # positional + positionals macros + binding
    transformers/
      scalar.cr
      collection.cr
      stdlib.cr                      # URI, Path, Time, ...
      enum.cr
    types/
      positive_int.cr
      non_negative_int.cr
      percentage.cr
      epoch_time.cr
      date.cr
      env_var.cr
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

## Decisions deferred to implementation

- **Completeness check (yes, minimal):** the macro layer emits a
  compile error when a `command` class has no `flag`, no
  `positional`/`positionals`, and no `subcommand` declarations. The
  shard does not check for "useful" content beyond that.
- **Symlink/alias completion** — not addressed in v1. A future
  enhancement may detect symlinked invocation and adjust the
  registered completion command name.
- **Completion-script cache invalidation** — not addressed in v1.
  Users re-install the script when needed.
