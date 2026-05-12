# Example: deploy

A demonstration CLI that wires up custom transformers, validators, and completers using [shell-auto_complete](../../).

## Build

```sh
crystal build examples/deploy/deploy.cr -o deploy
```

## Try it

```sh
./deploy --name my-app --region us-east-1
./deploy --name my-app --region us-east-1 --duration 30m --size 100MB
./deploy --name my-app --region us-east-1 --branch develop --dry-run
./deploy --name BAD --region us-east-1                # rejected by validator
./deploy --name my-app --region narnia                # rejected by validator
./deploy --name my-app --region us-east-1 --duration 5x  # rejected by transformer
./deploy --help
```

## Shell completion

```sh
eval "$(./deploy --shell-completion bash)"
```

After installation, tab completion on `--region` returns the allowed AWS regions; tab completion on `--branch` returns a hardcoded list of branches (simulating `git branch`).

## Custom transformers (`transform_with:`)

- **`--duration <Ns|Nm|Nh|Nd>`** parses human durations into total seconds.
- **`--size <NB|NKB|NMB|NGB|NTB>`** parses human-readable sizes into bytes.

## Custom validators (`validate_with:`)

- **`--name`** must be lowercase kebab-case, 1-40 chars.
- **`--region`** must be one of a fixed allowlist.

## Custom completers (`complete_with:`)

- **`--region`** completes to the same allowlist the validator enforces.
- **`--branch`** completes to a hardcoded branch list (would normally invoke `git branch`).

The completer methods receive a `Shell::AutoComplete::CompletionContext` and return `Array(String)`.

## Demonstrates

- `transform_with: :method_name` for arbitrary string-to-value parsing.
- `validate_with: :method_name` for arbitrary value validation.
- `complete_with: :method_name` for dynamic shell completion candidates.
- All three working together on a single flag (`--region`).
