# Example: toggles

A feature-flag / config management CLI built with
[shell-auto_complete](../../), used here as the introspection & config
showcase.

## Build

```sh
crystal build examples/toggles/toggles.cr -o toggles
```

## Try it

```sh
./toggles +dark-mode -telemetry beta            # enable dark-mode & beta, disable telemetry
./toggles --set db.host=localhost --set log:level=debug +x
                                                # config keys with dots and colons
./toggles --define BUILD=release +x             # define-only hash (assignment, no -key delete)
./toggles --organized +x                        # tri-state: explicit on
./toggles --no-organized +x                     # tri-state: explicit off
./toggles +x                                    # tri-state: unset (flag absent)
./toggles --mode canary +rollout                # constant-described flag with choices
./toggles --verbose 2 +x                        # --verbose takes an Int32 level here
```

Tokens for the variadic `changes` positional are `+name` / bare `name`
(enable) and `-name` (disable). At least one is required. Because the set
delta is in use, single-dash tokens like `-telemetry` parse as positionals
rather than flags. A delta is applied to a seed set of already-enabled flags
(`dark-mode`, `telemetry`, `beta`).

`--set` and `--define` are both `Hash(String, String)`. Keys may contain
letters, digits, `_`, `-`, `.`, and `:`. On `--set`, a bare `-key` deletes
that key from the accumulated hash; on `--define` (declared with
`hash_operations: false`) the bare `-key` delete form is a parse error, so
only `KEY=VALUE` assignment is accepted.

`--organized` is `Bool?`: absent (`nil`), `--organized` (`true`), or
`--no-organized` (`false`). The program calls `flag_given?(:organized)` to
tell an explicit `--no-organized` apart from the flag being absent and reports
all three states.

`--verbose` is shared from a `common_flag` catalog entry as a `Bool` switch,
then replaced at this command with an `Int32` level via `override: true`, so
here it takes a value (`--verbose 2`).

## Shell completion

```sh
./toggles --shell-completion bash > /etc/bash_completion.d/toggles
./toggles --shell-completion zsh  > ~/.zsh/completions/_toggles
./toggles --shell-completion fish > ~/.config/fish/completions/toggles.fish
```

## Demonstrates

- `SetDelta` variadic positional binding `Hash(String, Bool)`, applied to a
  seed `Set(String)` with `SetDelta.apply`
- `Hash(String, String)` flags with dotted and colon-bearing keys, and
  `hash_operations: false` to reject the bare `-key` delete form on one of them
- `Bool?` tri-state flag, with `flag_given?(:organized)` distinguishing an
  explicit `--no-organized` from the flag being absent
- `override: true` replacing an imported `common_flag` (`Bool --verbose`) with
  an `Int32 --verbose` level at the leaf command
- A flag description passed by the named `description:` option referencing a
  top-level constant (`MODE_HELP`), alongside `choices:`
- `disable_version_flag` turning off the `--version` intercept — useful when a
  bare token like `version` is meaningful program input (here, a feature flag
  named `version`) and intercepting `--version` would be surprising
