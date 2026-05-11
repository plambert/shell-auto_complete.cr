# shell-auto_complete

A Crystal shard for building command-line applications with parsing, `--help`, and shell completion (bash, zsh, fish) generated from a single macro-DSL definition.

## Why

Most CLI frameworks make you write argument parsing in one place and shell completions in another. This shard generates both from the same source — and the completions are smart: they call back into your binary for dynamic completions, support smart alias filtering, `@[Flags]` enum trailing-comma completion, and more.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  shell-auto_complete:
    github: plambert/shell-auto_complete.cr
    version: ~> 0.1
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

Completion is smart: it calls back into your binary for any dynamic candidates, applies alias filtering (`--dryrun` is shown when `--dry` is typed; `--dry-run` is shown when `--dry-` is typed), and supports `@[Flags]` enum completion with trailing-comma awareness.

## Features

- **One source of truth**: `command`, `flag`, `positional`, `positionals`, `subcommand` macros generate parser + help + completion.
- **Rich types**: numerics, booleans, strings, enums (incl. `@[Flags]`), `Array(T)`, `Set(T)`, `Hash(String, T)`, plus stdlib types (`URI`, `Path`, `Time`, `Log::Severity`, `Regex`) and synthetic types (`PositiveInt`, `Percentage`, `EpochTime`, `Date`, `EnvVar`).
- **Validation**: `range:`, `matches:`, `choices:`, custom `validate_with:`.
- **Transformer override**: `transform_with:` for custom string-to-value conversion.
- **Sub-subcommands**: arbitrarily nested command trees.
- **Three shells**: bash, zsh, fish — all with the same metadata.

## Documentation

- [Design spec](specs/2026-05-10-shell-autocomplete-api-design.md)
- [Implementation plan](specs/2026-05-10-shell-autocomplete-implementation-plan.md)
- [CHANGELOG](CHANGELOG.md)

## Contributing

Bug reports and PRs welcome.

## License

MIT (see LICENSE).
