# Example: containers

A docker/podman-style container CLI built with [shell-auto_complete](../../), showcasing dispatch, inherited global flags, a shared connection hook, and a reusable flag catalog.

## Build

```sh
crystal build examples/containers/containers.cr -o containers
```

## Try it

The base command carries the global connection flags. Subcommands inherit them through `parent:`, and a `before_run` hook resolves `--host` (or the `CONTAINER_HOST` env var) into a shared connection string before any subcommand runs.

```sh
./containers --version                       # 1.4.0
./containers version                          # same, via the version subcommand
./containers --help                           # global flags + subcommands

# Resolve the daemon explicitly or from the environment
./containers --host unix:///var/run/x.sock ps
CONTAINER_HOST=localhost:2375 ./containers ps

# Listing flags imported from the shared catalog
./containers --host x ps --format yaml -q
./containers --host x images --format json --digests

# Routing-union: because ps and images declare --format, it may appear
# *before* the subcommand on the base command line and still route correctly
./containers --host x --format json ps        # routes to ps, format = Json

# rm imports no listing flags, so --format is unknown there
./containers --host x --format json rm c1     # error: unknown flag: --format

# Missing daemon is a clean parse error from the before_run hook
./containers ps                               # error: no daemon: pass --host or set CONTAINER_HOST

# log-level enum with configured shortcut aliases, each with a short spelling
./containers --host x --silent ps             # --silent, -s => --log-level warn
./containers --host x -v ps                   # --verbose, -v => --log-level info
./containers --host x -w ps                   # -w is a short for the generated --warn
```

## Shell completion

```sh
./containers --shell-completion bash > /etc/bash_completion.d/containers
./containers --shell-completion zsh  > ~/.zsh/completions/_containers
./containers --shell-completion fish > ~/.config/fish/completions/containers.fish
```

## Demonstrates

- A base command with global flags inherited by subcommands via `parent:`
- `before_run` resolving `--host` (falling back to `CONTAINER_HOST`) into a shared `conn` property; an `ArgumentError` becomes a clean parse error when unresolvable
- A `common_flag` catalog with `import_flags` pulling different subsets per command: `ps` imports `--format,--filter,--quiet,--all`; `images` imports `--format,--filter,--quiet,--digests`; `rm` imports none
- The routing-union: `--format` accepted before `ps`/`images` but rejected at `rm`
- `tool_version "1.4.0"` plus `enable_version_subcommand`
- `shortcut_flags:` on the `--log-level` enum: `except:` filtering, `shorts:` giving a generated case switch a short spelling, and `aliases:` in both the bare and `{value:, short:, description:}` forms
- A `group: "Connection options"` heading and `help_sections:` reordering on `ps`
- Explicit placeholders (`HOST[:PORT]`, `--signal SIGNAL`) alongside type-derived ones (`table|json|yaml`, `TEXT`)
