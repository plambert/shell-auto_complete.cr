# shell-auto_complete

A Crystal shard for building command-line applications. You declare your commands, flags, and
positional arguments once with a small macro DSL, and the shard generates the argument parser,
`--help` text, and shell completion scripts (bash, zsh, fish) from that single definition.

## Introduction

Most CLI frameworks make you write argument parsing in one place and shell completions in another,
by hand, and keep them in sync forever. This shard generates both from the same source — and the
completions are smart: they call back into your binary, so dynamic candidates, alias filtering,
`@[Flags]` enum trailing-comma completion, and filesystem completion all stay correct as your CLI
changes.

A program is a tree of *command* classes. Each declares `flag`s and `positional`s, optionally
`subcommand`s, and a `run` method. `dispatch(ARGV)` parses the line, intercepts `--help` and
`--shell-completion`, routes to the right subcommand, and calls its `run`.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  shell-auto_complete:
    github: plambert/shell-auto_complete.cr
    version: ~> 2.0
```

Run `shards install`.

## Basic use

A single command with a few flags and a variadic positional:

```crystal
require "shell-auto_complete"

enum LogLevel
  Debug
  Info
  Warn
  Error
end

Shell::AutoComplete.command Build, name: "build", description: "Build the project" do
  flag message : String?, "--message", "--msg", "-m", "Build message"
  flag color : Bool = true, "--color", "-c", "Colorize output"
  flag log_level : LogLevel = LogLevel::Info, "--log-level", "Log verbosity", shortcut_flags: true
  flag jobs : Int32 = 1, "--jobs", "-j", "Parallel jobs", range: 1..64

  # Use Array(Path) to automatically enable file path completion in shells!
  positionals files : Array(Path), "Source files", min: 1

  def run
    puts "building #{files.size} file(s) with #{jobs} job(s), log=#{log_level}"
  end
end

Build.dispatch(ARGV)
```

Build it and the binary already supports the full surface:

```sh
build src/main.cr src/lib.cr --jobs 8 --debug   # --debug is a generated shortcut for --log-level debug
build --no-color src/main.cr                     # --no-color is generated from the Bool flag
build --help
build --shell-completion bash > /etc/bash_completion.d/build
```

`--help` is generated from the same declarations, with a placeholder showing what each flag expects:

```text
Usage: build [options] <files...>

Build the project

Options:
  --message, --msg, -m TEXT     Build message
  --color, -c                   Colorize output
  --log-level debug|info|warn|error  Log verbosity
  --jobs, -j NUMBER             Parallel jobs

Positional arguments:
  <files...>                    Source files
```

Adding subcommands is a second command class plus `subcommand`:

```crystal
Shell::AutoComplete.command Tool, name: "tool", description: "Project tool" do
  flag verbose : Bool = false, "--verbose", "-V", "Verbose output"
  subcommand Build
end

Tool.dispatch(ARGV)
```

Now `tool build ...`, `tool --verbose build ...` (a parent flag before the subcommand), and `tool
build --help` all work, and completion descends into subcommands.

For step-by-step recipes ("accept one or more files", "validate only even integers above 5", "accept
`--include`/`--exclude` keeping their order"), see **[cookbook.md](cookbook.md)**. For complete
runnable programs, see **[examples/](examples/)**.

## Reference

### Defining a command

```crystal
Shell::AutoComplete.command ClassName, name: "cmd", description: "...", **options do
  # flags, positionals, subcommands, before_run, version config
  def run
    # parsed values are available as methods (port) or ivars (@port)
  end
end

ClassName.dispatch(ARGV)
```

`command` options:

* `name:` — the program/subcommand name (defaults to the basename of `PROGRAM_NAME`).
* `aliases:` — alternate names this command answers to when routed as a subcommand (see
  [Subcommands and routing](#subcommands-and-routing)).
* `description:` — one-line description shown in help.
* `parent:` — inherit another command's flags (see [Inheriting flags](#inheriting-flags)).
* `header:` / `footer:` — prose before the `Usage:` line and after the body.
* `usage:` — override the generated `Usage:` line.
* `help_sections:` — order/omit the middle help sections, any subset of `[:description, :options,
  :subcommands, :positionals]`.

`dispatch(argv, rescue_errors: true, stdout: STDOUT, stderr: STDERR)` parses and runs. With
`rescue_errors: true` (default) a `ParseError` prints `cmd: <message>` to stderr and exits 1; with
`false` it raises.

### Flags

```crystal
flag declaration : Type, "--long", "-s", "--alias", "Description", **options
```

The first non-dash, non-placeholder string literal is the description; `--x` strings are the
canonical spelling and long aliases; a single `-x` is the short form. A `Bool`/`Bool?` flag is a
*switch* (no value, auto `--no-` negation); every other type takes a value. Give a value flag a
default with `=`; a nilable type without one defaults to `nil`.

Flag options:

| Option | Effect |
|---|---|
| `choices:` | restrict to a set (`%w[a b c]`); drives validation, completion, placeholder |
| `range:` | numeric range validation (`1..65535`) |
| `matches:` | regex validation for strings |
| `transform_with:` | class method `String -> value` (may raise `ArgumentError`) |
| `validate_with:` | class method `value -> Bool \| String` (`String` = error message) |
| `complete_with:` | class method `CompletionContext -> Array(String)` for dynamic completion |
| `negatable: false` | suppress the generated `--no-` for a switch |
| `hidden: true` | omit from help (still parses) |
| `delimiter:` | required on `Array`/`Set`: `","` splits each value, `nil` is one element per occurrence |
| `set_operations: true` | `Set` flag treats `+x` add, `-x` remove, bare add |
| `hash_operations: false` | `Hash` flag rejects the bare `-key` delete form |
| `shortcut_flags:` | enum flag: `true`, or `{only:/except:/shorts:/aliases:}` (see [Enums](cookbook.md#enums)) |
| `bare_number:` | scalar flag: accept `-20`/`+50` as the flag and its value at once |
| `placeholder:` | help metavar for the value |
| `group:` | render under a named help heading |
| `immediate:` | switch flag: run a handler and exit as soon as it appears |
| `override: true` | replace an inherited or imported flag of the same spelling |
| `description:` | the description as a named option (needed before a bare constant) |

Per-element `transform_with:`/`validate_with:` apply to `Array`/`Set`/`Hash` element values too.

### Value types

Out of the box, value flags and positionals accept: every `Int*`/`UInt*`/`Float*`, `String`, `Char`,
`Bool`/`Bool?`, `Path`, `File`, `Dir`, `URI`, `Time`, `Regex`, `Log::Severity`, and
`Socket::IPAddress`. Collections: `Array(T)`, `Set(T)`, `Hash(String, T)`. Synthetic constrained
types ship under `Shell::AutoComplete::Types`: `PositiveInt`, `NonNegativeInt`, `Percentage`,
`EpochTime`, `Date`, `EnvVar`, `DirPath`, and the `SetDelta` positional type. A union type, or an
element type with no built-in parser (`Tuple(String, String)`), needs an explicit `transform_with:`.

### Placeholders

A value flag's help shows a placeholder derived from its type (`NUMBER`, `TEXT`, `FILE`, `URL`,
`KEY=VALUE`, pipe-joined values for small enums/`choices:`). Override it three ways: an ALL-CAPS
string before the description (`"--port", "PORT", "..."`), embedded in the flag string
(`"--after TIME"`), or `placeholder: "HOST[:port]"`. A leftover string literal the shard can't place
is a compile error. Switches take no placeholder.

### Positionals

```crystal
positional name : String, "Description"          # one required (nilable type = optional)
positionals files : Array(Path), "Description", min: 1, max: 10   # variadic, at most one per command
```

`Path`/`File`/`Dir` complete against the filesystem; `File`/`Dir` also check existence, and
`Shell::AutoComplete::Types::DirPath` completes directories without checking. A
`Shell::AutoComplete::Types::SetDelta` variadic positional binds `+name`/`-name`/`name` tokens into
a `Hash(String, Bool)`. The placeholder in the usage line is derived from the property name
(`<files...>`), not an ALL-CAPS string.

### Subcommands and routing

`subcommand ChildClass` (in the parent's block, or by reopening the parent class) registers a child.
Routing walks past the parent's own flags to find the subcommand word, so a shared flag may sit
before or after it. When a subcommand declares a flag the parent doesn't, the parent still routes
past it (consulting the subcommand's flag arity) and the subcommand accepts or rejects it — so
`tool --format json list` works while `tool --format json other` is rejected at `other`. Subcommands
disagreeing on whether a shared spelling takes a value is a compile error.

A subcommand may answer to more than one name with `aliases:` on its `command` macro:

```crystal
Shell::AutoComplete.command Move,
  name: "move",
  aliases: ["mv", "rename"],
  description: "Move or rename a file",
  parent: Files do
  # ...
end
```

Each alias routes to the command exactly as its canonical name does, is offered in completion, and
is listed beside the name in the parent's help (`move, mv, rename`). A canonical name match on any
subcommand wins over an alias, so an alias can never shadow another command's real name.

`external_subcommands` (on a root command's block) adds git-style external dispatch: a subcommand
word matching no declared subcommand is looked up on `PATH` as `<command_name>-<word>`, and if found
the process is replaced (`exec`) with it, passing every argument after the word. Declared
subcommands always win; a word containing a path separator is never looked up; and when nothing is
found the usual `unknown subcommand` error is raised. It works with declared subcommands or on its
own (a pure PATH-dispatch tool), and discovered external subcommands are offered in completion
alongside declared ones. Declaring it on a `parent:`-derived command is a compile error.

`search_path:` restricts the lookup to a fixed, colon-separated directory list instead of `PATH`. A
relative entry resolves against the directory holding the running binary, so
`external_subcommands search_path: "commands:../lib/commands:/etc/tool/commands"` for a binary at
`/opt/tool/bin/tool` searches `/opt/tool/bin/commands`, `/opt/tool/lib/commands`, and
`/etc/tool/commands`, in order, regardless of the caller's `PATH`. Both dispatch and completion use
it.

### Inheriting flags

`parent: OtherCommand` on the `command` macro makes a command inherit every flag the parent declares
— real properties, parsed and completed, shown under an `Inherited options:` heading. Inheritance
chains through levels and is independent of `subcommand` routing. A leaf flag colliding with an
inherited one is a compile error unless it uses `override: true`.

### Sharing flags across commands

```crystal
Shell::AutoComplete.common_flag :format, format : Format = Format::Table, "--format", "Output format"
# inside a command:
import_flags :format, :quiet
```

`common_flag` defines a reusable flag once, outside any command; `import_flags` replays a chosen
subset inside a command, where each behaves exactly as a directly declared flag (registry, help,
completion, duplicate detection). Different commands import different subsets.

Call `common_flag` at the **top level**, not inside a `module`. It defines its replay macro in the
scope where it expands, while `import_flags` resolves that macro from the command class — so a
catalog nested in a module is invisible even to commands in that same module
(`undefined local variable '__sac_common_flag_<name>'`).

### Ordered flag groups

```crystal
ordered_flag_group "Filter rules (in command-line order)",
  {"--include" => "PATTERN: include", "--exclude" => "PATTERN: exclude"} do |key, value|
  @rules << {key, value}   # key has "--" stripped; runs at parse time, in argv order
end
```

For the rsync/tar shape where the interleaving between flags is the semantics. The block runs once
per occurrence in command-line order; raising `ArgumentError` becomes a parse error. Value-taking
members only.

### Delimited flags

```crystal
delimited_flag command : Array(String), "--command", "-c", "Command to run"
```

Captures a run of raw argv tokens into a collection, ending at a delimiter (default `--`, which is
discarded). Every token in the run is appended verbatim, so flag-looking tokens are taken literally
— the `env`/`xargs`/`time` shape where a whole sub-command is embedded:

```text
tool --command echo hello -- --json path
#   @command => ["echo", "hello"]      (built with .new then <<(String) per token)
#   @json    => true                   (parsing resumes after the delimiter)
```

The declared type only has to answer `.new` and `<<(String)` (`Array(String)`, `Set(String)`, or a
custom type). If the delimiter never appears, capture runs to the end of argv; when the flag is
absent the property is an empty `.new` (or `nil`, if the type is nilable). The delimiter is
configurable with `delimiter:`. Only the space-separated form is captured — `--command=x` is not a
delimited invocation. Composes with subcommands through `parent:` inheritance: the routing walk
skips the capture to find the subcommand word.

`external_command: true` marks the captured value as a command line for completion: inside the
capture the shell completes the first word as a command name and the rest with that command's own
completion (falling back to file completion) — via `_command_offset` (bash), `_normal` (zsh), and
`complete -C` (fish). It changes completion only, not parsing.

### before_run hooks

```crystal
before_run do
  # runs on the parsed instance after parsing, before run
end
```

For once-before-run setup that mutates shared state or can fail (open a connection, configure a
global, resolve an inherited flag, cross-flag validation). Raising `ArgumentError` becomes a clean
parse error. Hooks collect down a `parent:` hierarchy and run parent-first, so subcommands inherit
base setup without `super`. They run only for the command whose `run` executes.

### Version

`tool_version "1.2.3"` and `tool_name "name"` set the strings (plain strings; both inherit via
`parent:`). `--version` with no subcommand prints `<name> <version>` and exits;
`enable_version_subcommand` adds a `version` subcommand printing the same line. Without
`tool_version`, the version is the nearest visible `VERSION` constant, falling back to
`shards version` at build time. Declaring your own `--version` flag, or `disable_version_flag`,
turns the intercept off.

### Introspection

On a parsed instance: `flag_given?(:name)` reports whether a flag was set under any spelling
(distinguishing an explicit value from absence); `parsed_occurrences : Array({String, String?})` is
an ordered log of every flag occurrence (spelling as typed, raw value or `nil`).

### Shell completion

Every command gets `--shell-completion <bash|zsh|fish>`, which prints a script that calls back into
your binary for candidates:

```sh
eval "$(mytool --shell-completion bash)"          # try it in the current shell
mytool --shell-completion zsh  > ~/.zsh/completions/_mytool
mytool --shell-completion fish > ~/.config/fish/completions/mytool.fish
```

By default the generated script's callback invokes the command by name, so it resolves through
`PATH` — the right behavior for an installed script. For testing a dev build, add `--absolute` (or
`-a`): the callback then invokes this exact binary by its resolved absolute path, so
`eval "$(bin/mytool --shell-completion bash --absolute)"` completes against `bin/mytool` even when a
different `mytool` is on `PATH`. The command name still registers the completion, so re-`eval` the
installed script when you're done. Don't bake `--absolute` into an installed script — the path goes
stale when the binary moves.

Completion covers subcommands (declared and external), flag names (with alias filtering),
`choices:`/enum values, `@[Flags]` trailing commas, dynamic `complete_with:` candidates, embedded
commands (`delimited_flag ..., external_command: true`), and native filesystem completion for
`Path`/`File`/`Dir`.

Using `String`, the shell completion won't complete anything. If you are expecting one of a fixed
list of values, either use an Enum, or set `choices: %w(a b c)` on the flag.

## Examples

Runnable programs under [examples/](examples/), each with its own README:

* **[cat](examples/cat/)** — BSD/GNU `cat` clone: multiple `Bool` flags, a variadic `Array(Path)`
  positional, `-` as a stdin marker, and `bare_number:` for a `head -20` shorthand.
* **[deploy](examples/deploy/)** — custom `transform_with:`, `validate_with:`, and `complete_with:`
  on one command, including all three on a single flag.
* **[multitool](examples/multitool/)** — every bundled value type and synthetic type, across a
  subcommand tree.
* **[containers](examples/containers/)** — a docker-style CLI: `parent:` inheritance, `before_run`,
  a `common_flag` catalog with `import_flags`, the routing union, `--version`, and `shortcut_flags`
  configuration.
* **[sync](examples/sync/)** — an rsync-style CLI: `ordered_flag_group`, `parsed_occurrences`,
  `choices:`/`range:`/`matches:`, `set_operations:`, an `immediate:` flag, and per-element
  transforms.
* **[toggles](examples/toggles/)** — a feature-flag CLI: a `SetDelta` positional, dotted/colon
  `Hash` keys, `Bool?` tri-state with `flag_given?`, and `override:`.

## Documentation

* [Cookbook](cookbook.md) — task-oriented recipes.
* [Design spec](specs/2026-05-10-shell-autocomplete-api-design.md)
* [CHANGELOG](CHANGELOG.md)

## Contributing

Bug reports and PRs welcome.

## License

MIT (see LICENSE).
