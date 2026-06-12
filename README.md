# shell-auto_complete

A Crystal shard for building command-line applications with parsing, `--help`, and shell completion
(bash, zsh, fish) generated from a single macro-DSL definition.

## Why

Most CLI frameworks make you write argument parsing in one place and shell completions in another.
This shard generates both from the same source — and the completions are smart: they call back into
your binary for dynamic completions, support smart alias filtering, `@[Flags]` enum trailing-comma
completion, and more.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  shell-auto_complete:
    github: plambert/shell-auto_complete.cr
    version: ~> 2.0
```

Run `shards install`.

## Quick start

```crystal
require "shell-auto_complete"

enum LogLevel
  Debug
  Info
  Warn
  Error
end

Shell::AutoComplete.command MyApp::Build, name: "build", description: "Build the project" do
  flag message : String?, %w(--message --msg -m), "Build message"
  flag color : Bool = true, "--color", "-c", "Colorize output"
  flag log_level : LogLevel = LogLevel::Info, "--log-level", "Log verbosity", shortcut_flags: true
  flag port : Int32?, "--port", "Port number", range: 1..65535

  positional name : String, "Build name"
  positionals files : Array(Path), "Source files", min: 1

  def run
    # use @message, @color, @log_level, @port, @name, @files
    puts "Building #{@name} on port #{@port}..."
  end
end

MyApp::Build.dispatch(ARGV)
```

Now your binary supports:

```sh
mybuild myapp src/main.cr src/lib.cr --port 8080 --debug
mybuild --help
mybuild --shell-completion bash > /etc/bash_completion.d/mybuild
```

## Shell completion

The shard generates completion scripts for bash, zsh, and fish. Install one of them:

```sh
# Bash
eval "$(mybuild --shell-completion bash)"

# Zsh
mybuild --shell-completion zsh > _mybuild  # then add to fpath

# Fish
mybuild --shell-completion fish > ~/.config/fish/completions/mybuild.fish
```

Completion is smart: it calls back into your binary for any dynamic candidates, applies alias
filtering (`--dryrun` is shown when `--dry` is typed; `--dry-run` is shown when `--dry-` is typed),
and supports `@[Flags]` enum completion with trailing-comma awareness.

Positionals complete too. A positional with `complete_with:` calls back into your binary for
candidates, and path-typed positionals (`Path`, `File`, `Dir`) delegate to the shell's native
filesystem completion — so `mybuild src/<TAB>` expands real paths with `~`-expansion, trailing
slashes, and coloring intact.

## Set-delta positionals

A variadic positional typed `Shell::AutoComplete::Types::SetDelta` accepts `+name`, `-name`, and
bare `name` tokens and binds them into a `Hash(String, Bool)` — useful for toggling a set of things
on and off in one invocation. `SetDelta.apply` applies that delta to an existing `Set(String)`:

```crystal
Shell::AutoComplete.command Features, name: "features", description: "Toggle features" do
  positionals changes : Shell::AutoComplete::Types::SetDelta, "+name to enable, -name to disable"
  def run
    enabled = load_enabled # Set(String)
    Shell::AutoComplete::Types::SetDelta.apply(enabled, changes)
  end
end
```

```sh
features +dark-mode -telemetry beta   # changes => {"dark-mode" => true, "telemetry" => false, "beta" => true}
```

`+name` maps to `true`, `-name` to `false`, and a bare `name` to `true`; the last token wins for a
repeated key, and `min:`/`max:` bound the number of distinct keys. The single-dash `-name` form is
accepted as a positional rather than an unknown flag, while real flags (and `--`) keep working as
usual.

## Shared flags across subcommands

A command may inherit another command's flags with `parent:`. Inherited flags become real
properties on the leaf, parse before or after the subcommand word, render under an
`Inherited options:` heading in the leaf's help, and complete in both positions. Routing
commands can also carry their own flags (`app --init` works even with subcommands present).

```crystal
Shell::AutoComplete.command App, name: "app", description: "My tool" do
  flag verbose : Bool = false, "--verbose", "-V", "Verbose output"
  flag server : String = "localhost", "--server", "Server address"
end

Shell::AutoComplete.command Scan, name: "scan", description: "Scan things", parent: App do
  flag target : String?, "--target", "Scan target"

  def run
    # verbose, server, and target are all available here
  end
end

class App
  subcommand Scan
end
```

```sh
app --verbose scan --target db   # shared flags work before the subcommand word...
app scan --verbose --target db   # ...and after it
```

Redeclaring an inherited (or mixin-stamped) spelling is a compile error; add `override: true`
to replace the existing flag wholesale. Every spelling a declaration produces — canonical,
aliases, short forms, `--no-` negations, enum shortcut switches — is checked for collisions
at compile time.

## Help placeholders

Value flags show what they consume: `--port PORT`, `--level debug|info|warn`. Placeholders
derive from the declared type (`NUMBER`, `TEXT`, `FILE`, `URL`, `KEY=VALUE`, pipe-joined
enum/`choices:` values, ...) or can be given explicitly three ways:

```crystal
flag port : Int32?, "--port", "PORT", "Server port"          # before the description
flag after : String?, "--after TIME", "Skip entries before"  # embedded in the flag string
flag host : String?, "--host", "Bind host", placeholder: "HOST[:port]"
```

## Ordered flag groups

When the interleaving between different flags is the semantics (rsync-style filter rules),
declare them as a group; occurrences are delivered to the block in command-line order, at
parse time:

```crystal
ordered_flag_group "Filter rules (applied in command-line order)",
  {"--include" => "PATTERN: include matching files",
   "--exclude" => "PATTERN: exclude matching files"} do |key, value|
  @rules << {key, value} # key arrives with "--" stripped
end
```

## Features

* **One source of truth**: `command`, `flag`, `positional`, `positionals`, `subcommand`,
  `ordered_flag_group` macros generate parser + help + completion.
* **Rich types**: numerics, booleans (incl. `Bool?` tri-state switches), strings, enums (incl.
  `@[Flags]`), `Array(T)`, `Set(T)`, `Hash(String, T)`, plus stdlib types (`URI`, `Path`, `Time`,
  `Log::Severity`, `Regex`) and synthetic types (`PositiveInt`, `Percentage`, `EpochTime`, `Date`,
  `EnvVar`).
* **Validation**: `range:`, `matches:`, `choices:`, custom `validate_with:` — applied per element on
  collection flags too.
* **Transformer override**: `transform_with:` for custom string-to-value conversion, per element on
  collections.
* **Explicit splitting**: collection flags state their behavior with `delimiter: ","` or
  `delimiter: nil` — a required choice, so comma-containing data is never silently corrupted.
* **Enum shortcut switches**: `shortcut_flags: true`, or a config with `only:`/`except:` case
  filters and `aliases:` (`{quiet: :warn}`) that resolve last-wins against real shortcuts.
* **Introspection**: `flag_given?(:name)` distinguishes an explicit value from a default;
  `parsed_occurrences` is a raw, ordered log of every flag occurrence as typed.
* **Help control**: `help_sections:` reorders sections, `group:` puts flags under their own heading,
  descriptions/headers/footers accept constant and method references, `immediate:` flags fire before
  full-line validation (`--list-formats` style).
* **Compile-time safety**: duplicate flag spellings, missing `delimiter:`, stray string literals,
  and invalid option combinations are compile errors, not latent bugs.
* **Sub-subcommands**: arbitrarily nested command trees, with shared flags accepted on either side
  of each subcommand word.
* **Three shells**: bash, zsh, fish — all with the same metadata.

## Documentation

* [Design spec](specs/2026-05-10-shell-autocomplete-api-design.md)
* [Implementation plan](specs/2026-05-10-shell-autocomplete-implementation-plan.md)
* [CHANGELOG](CHANGELOG.md)

## Contributing

Bug reports and PRs welcome.

## License

MIT (see LICENSE).
