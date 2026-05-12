# Example: multitool

A demonstration CLI that exercises every bundled transformer and synthetic type in [shell-auto_complete](../../).

## Build

```sh
crystal build examples/multitool/multitool.cr -o multitool
```

## Subcommand tree

```
multitool
├── scan
│   ├── deep    — numeric scalars (Int8–UInt64, Float32, Float64, PositiveInt, NonNegativeInt)
│   └── quick   — String, Char, Bool, Percentage, EpochTime, Date
├── transform   — Array(T), Set(T), Hash(String, T), enums (including @[Flags])
└── config
    ├── get     — Path, File, Dir, Regex
    └── set     — URI, Time, Socket::IPAddress, Log::Severity, EnvVar
```

## Try it

```sh
./multitool --help
./multitool scan deep --int32 42 --float64 3.14
./multitool scan deep --positive-int 5 --non-negative-int 0
./multitool scan quick --string hello --char x --bool --percentage 75.5
./multitool scan quick --epoch-time 1700000000 --date 2026-05-10
./multitool transform --tags a,b,c --env FOO=bar --log-level debug
./multitool transform --perms read,write
./multitool transform --debug                   # shortcut flag for --log-level debug
./multitool config get --path /tmp --regex 'foo.*bar'
./multitool config set --url https://example.com --severity warn
./multitool config set --env-var MY_VAR --ip 127.0.0.1:8080 --time 2026-05-10T12:00:00Z
```

## Shell completion

```sh
./multitool --shell-completion bash > /etc/bash_completion.d/multitool
./multitool --shell-completion zsh  > ~/.zsh/completions/_multitool
./multitool --shell-completion fish > ~/.config/fish/completions/multitool.fish
```

## Demonstrates

- Subcommands (`scan`, `transform`, `config`) and sub-subcommands (`scan deep`, `scan quick`, `config get`, `config set`)
- Every bundled scalar transformer: `Int8`, `Int16`, `Int32`, `Int64`, `UInt8`, `UInt16`, `UInt32`, `UInt64`, `Float32`, `Float64`, `String`, `Char`, `Bool`
- Every bundled stdlib transformer: `Path`, `File` (→ Path), `Dir` (→ Path), `URI`, `Time`, `Socket::IPAddress`, `Log::Severity`, `Regex`
- Every bundled collection transformer: `Array(T)`, `Set(T)`, `Hash(String, T)`
- Ordinary enum with `shortcut_flags: true` — `--log-level debug` and `--debug` both work
- `@[Flags]` enum with comma-separated values — `--perms read,write`
- Every shipped synthetic type wired via `transform_with:` / `validate_with:`:
  - `Shell::AutoComplete::Types::PositiveInt` (`--positive-int`)
  - `Shell::AutoComplete::Types::NonNegativeInt` (`--non-negative-int`)
  - `Shell::AutoComplete::Types::Percentage` (`--percentage`)
  - `Shell::AutoComplete::Types::EpochTime` (`--epoch-time`)
  - `Shell::AutoComplete::Types::Date` (`--date`)
  - `Shell::AutoComplete::Types::EnvVar` (`--env-var`)
