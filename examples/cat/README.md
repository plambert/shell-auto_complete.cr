# Example: cat clone

A BSD/GNU-style `cat` implementation built with [shell-auto_complete](../../).

## Build

```sh
crystal build examples/cat/cat.cr -o cat
```

## Usage

```sh
./cat                          # read from stdin
./cat file.txt                 # read one file
./cat file1.txt file2.txt      # concatenate multiple files
./cat -                        # explicit stdin
./cat -n file.txt              # number every line
./cat -b file.txt              # number non-blank lines (overrides -n)
./cat -s file.txt              # squeeze multiple blank lines into one
./cat -v file.txt              # show non-printing chars (^X, M-, ^?)
./cat -u file.txt              # flush after each line
./cat --lines 20 file.txt      # stop after 20 lines
./cat -20 file.txt             # the same, in the head -20 shape
```

## Flags

| Short | Long                  | Effect                                            |
|-------|-----------------------|---------------------------------------------------|
| `-b`  | `--number-nonblank`   | Number non-blank lines (overrides `-n`)           |
| `-s`  | `--squeeze-blank`     | Squeeze consecutive blank lines                   |
| `-n`  | `--number`            | Number all lines                                  |
| `-u`  | `--unbuffered`        | Flush stdout after each line                      |
| `-v`  | `--show-nonprinting`  | Render non-printing bytes as `^X` / `M-` notation |
| `-NUM`| `--lines N`           | Stop after N lines (`-20` is `--lines 20`)        |

## Shell completion

```sh
./cat --shell-completion bash > /etc/bash_completion.d/cat
./cat --shell-completion zsh  > ~/.zsh/completions/_cat
./cat --shell-completion fish > ~/.config/fish/completions/cat.fish
```

## Demonstrates

- Multiple `Bool` flags with both short and long forms
- `--no-foo` negation auto-generated for each Bool flag
- Variadic `positionals` of type `Array(Path)`
- Reading positional `-` as a stdin marker
- `bare_number:` on `--lines`, so `-20` is the flag and its value in one token,
  validated by the same `range:` as the long form
- `--help` and `--shell-completion` built-in flags provided by the shard
