# Cookbook

Task-oriented recipes for [shell-auto_complete](README.md). Each entry is named for what you are
trying to do; the answer shows the code and explains the shard's own terms as they come up.

Every recipe assumes you are inside a command block:

```crystal
require "shell-auto_complete"

Shell::AutoComplete.command MyTool, name: "mytool", description: "..." do
  # recipes go here
  def run
    # your logic; read each flag as a method (port) or ivar (@port)
  end
end

MyTool.dispatch(ARGV)
```

`dispatch(ARGV)` parses, handles `--help` / `--shell-completion`, routes subcommands, runs your
`run`, and on a bad command line prints `mytool: <message>` and exits 1. Pass `rescue_errors: false`
to raise instead (see [Handle parse errors yourself](#handle-parse-errors-yourself)).

## Flags

### Accept a boolean flag

```crystal
flag color : Bool = false, "--color", "Colorize output"
```

A `Bool` flag is a *switch*: it takes no value. `--color` sets it true, and the shard auto-generates
`--no-color` to set it false. Read it as `color` in `run`.

### Accept a flag that takes a value

```crystal
flag port : Int32?, "--port", "Server port"
flag name : String = "build", "--name", "Build name"
```

Any non-`Bool` type takes a value (`--port 8080` or `--port=8080`). A nilable type (`Int32?`)
defaults to `nil`; give a non-nilable type a default with `=`. The shard parses the string into the
declared type for you — see [the type list](README.md#value-types).

### Give a flag a short form and long aliases

```crystal
flag message : String?, "--message", "--msg", "-m", "Commit message"
```

List extra spellings as more string literals. Anything starting with `--` is a long alias; a single
`-x` is the short form (one per flag). The first non-dash string is the description. All spellings
parse, complete, and (for switches) get their own `--no-` negation.

### Make a flag accept only a fixed set of values

```crystal
flag level : String?, "--level", "Log level", choices: %w[debug info warn error]
```

`choices:` validates the value against the set and drives both completion and the help placeholder
(`--level debug|info|warn|error`). For a closed set known at compile time, an `enum` is often nicer
— see [Accept one of an enum's values](#accept-one-of-an-enums-values).

### Give a flag a default value

```crystal
flag retries : Int32 = 3, "--retries", "Retry count"
```

Use `=` in the declaration. A nilable type with no `=` defaults to `nil`; the property is then
`Int32?`, so check for `nil` in `run`.

### Accept a three-way boolean: on, off, or not set

```crystal
flag organized : Bool?, "--organized", "Mark records organized"
```

A `Bool?` switch is tri-state: `--organized` → `true`, `--no-organized` → `false`, untouched →
`nil`. This is the primitive for "only change the field if the user said so" (config layering,
partial updates). To tell an explicit `--no-organized` from absence when both read as a value, use
[`flag_given?`](#know-whether-a-flag-was-given).

### Stop a boolean from generating `--no-`

```crystal
flag force : Bool = false, "--force", "Force the operation", negatable: false
```

`negatable: false` suppresses the auto-generated `--no-force`. This also frees the `--no-force`
spelling if another flag wants it.

### Show in `--help` what a flag expects

A value flag renders a *placeholder* (metavar) after its name. The shard derives one from the type
(`--port NUMBER`, `--name TEXT`, `--out FILE`, `--at TIME`, `--set KEY=VALUE`, pipe-joined values
for small enums and `choices:`). Override it three ways:

```crystal
flag port : Int32?, "--port", "PORT", "Server port"          # ALL-CAPS before the description
flag after : String?, "--after TIME", "Skip entries before"  # embedded in the flag string
flag host : String?, "--host", "Bind address", placeholder: "HOST[:port]"
```

The ALL-CAPS form must come before the description. A leftover string literal the shard can't place
is a compile error (it catches typos), so you cannot pass a stray extra string. Switches take no
placeholder.

### Hide a flag from help

```crystal
flag internal : Bool = false, "--internal", "Internal toggle", hidden: true
```

`hidden: true` keeps the flag working (it still parses) but omits it from `--help` output.

## Validating and transforming values

### Restrict a number to a range

```crystal
flag port : Int32?, "--port", "Server port", range: 1..65535
```

`range:` validates the parsed number; out-of-range input is rejected at parse time. (The range does
not change the help placeholder — that still derives from the type.)

### Require a string to match a pattern

```crystal
flag rename : String?, "--rename", "Rename rule", matches: /\As\/[^\/]*\/[^\/]*\/\z/
```

`matches:` validates the string against a regex.

### Validate a value with custom logic, like "only even integers above 5"

```crystal
flag count : Int32?, "--count", "An even number greater than 5", validate_with: :check_count

def self.check_count(value : Int32) : Bool | String
  return "must be greater than 5" unless value > 5
  return "must be even" unless value.even?
  true
end
```

`validate_with:` names a class method that receives the parsed value and returns `true` (ok) or a
`String` error message. Returning the message rejects the value with that exact text. This runs at
parse time, so the error surfaces before `run`.

### Convert a value into a custom shape, like "30m" into seconds

```crystal
flag timeout : Int32 = 0, "--timeout", "e.g. 30s, 5m, 2h", transform_with: :parse_duration

def self.parse_duration(value : String) : Int32
  m = value.match(/\A(\d+)([smh])\z/) || raise ArgumentError.new("bad duration: #{value}")
  m[1].to_i * {"s" => 1, "m" => 60, "h" => 3600}[m[2]]
end
```

`transform_with:` names a class method that turns the raw string into the value. Raising
`ArgumentError` rejects the input with a clean parse error. The return type can differ from the
declared type (the property storage adapts), so a `--timeout` declared `Int32` can be fed by a
parser that accepts `"5m"`.

### Attach a converter to a flag by name

```crystal
flag timeout : Int32 = 0, "--timeout", "..."   # no transform_with:

def self.__arg_transform_timeout(value : String) : Int32
  # ...
end
```

If a class method is named `__arg_transform_<flag>` or `__arg_validate_<flag>`, the shard uses it
for that flag automatically — the same as `transform_with:` / `validate_with:` but discovered by
name.

## Positional arguments and files

### Accept one required positional argument

```crystal
positional name : String, "Project name"
```

`positional` declares a single positional. A non-nilable type is required; the description is the
string after the type.

### Accept an optional positional

```crystal
positional name : String?, "Project name (optional)"
```

A nilable type makes the positional optional; it is `nil` when absent.

### Accept one or more files as arguments

```crystal
positionals files : Array(Path), "Files to process", min: 1
```

`positionals` (plural) is the *variadic* slot — at most one per command. `min:`/`max:` bound the
count. Use `Array(Path)` for paths, `Array(String)` for plain words. Leading and trailing scalar
`positional`s may sit on either side of the variadic.

### Complete file and directory paths

```crystal
positional src : File, "Source file"
positional dir : Dir, "Target directory"
positionals files : Array(Path), "Inputs"
```

`Path`, `File`, and `Dir` complete against the filesystem using the shell's native file completion
(with `~` expansion, trailing slashes, coloring). `File`/`Dir` additionally check existence at parse
time and complete files/directories respectively; `Path` accepts anything.

### Complete a directory that doesn't exist yet, or lives on another host

```crystal
flag download_dir : Shell::AutoComplete::Types::DirPath?, "--download-dir",
  "Destination on the daemon's host"
```

`Dir` checks that the directory exists locally, which is wrong for a path handed to a remote daemon
or one the program `mkdir_p`s on first run — both are valid input it would reject. `Path` accepts
them but offers files alongside directories when completing. `DirPath` completes directories only,
like `Dir`, and checks nothing, like `Path`. Values are stored as `Path`, same as the other three.

### Toggle a set of things on and off in one invocation

```crystal
positionals changes : Shell::AutoComplete::Types::SetDelta, "+name to enable, -name to disable", min: 1

def run
  enabled = Shell::AutoComplete::Types::SetDelta.apply(load_enabled, changes)
end
```

A `SetDelta` variadic positional accepts `+name`, `-name`, and bare `name` tokens and binds them to
a `Hash(String, Bool)` (`+name`/`name` → true, `-name` → false, last write wins). `SetDelta.apply`
folds that delta into an existing `Set(String)`. Using `SetDelta` flips on a parser mode where a
single-dash token that matches no flag is treated as a positional, so a command with a `SetDelta`
positional cannot also have subcommands (its `+name`/`-name` tokens would be read as the subcommand
word).

## Array, Set, and Hash parameters

### Use repeated flags to fill an Array

```crystal
flag tag : Array(String) = [] of String, "--tag", "Tag (repeatable)", delimiter: nil
```

A collection type accumulates across occurrences. `delimiter:` is **required** on `Array`/`Set`
flags and states how each occurrence is split: `nil` takes the whole value as one element (so
`--tag a --tag b` → `["a", "b"]`), `","` splits each value on commas.

### Accept a comma-separated list

```crystal
flag ports : Array(Int32) = [] of Int32, "--ports", "Comma-separated ports", delimiter: ","
```

With `delimiter: ","`, `--ports 80,443` → `[80, 443]`. Choose `nil` instead when the values can
themselves contain commas (paths, regexes, URLs, titles) — making the choice explicit is why
`delimiter:` is mandatory.

### Accept a set you can add to and remove from

```crystal
flag features : Set(String) = Set(String).new, "--with", "e.g. +cache,-logging", delimiter: ",", set_operations: true
```

`set_operations: true` makes a `Set` flag treat `+name` as add, `-name` as remove, and a bare `name`
as add, applied left to right. So `--with +cache,-logging` adds `cache` and removes `logging`.

### Accept key=value pairs

```crystal
flag env : Hash(String, String) = {} of String => String, "--env", "Environment KEY=VALUE"
```

A `Hash(String, T)` flag parses `KEY=VALUE`. Keys may contain letters, digits, `_`, `-`, `.`, and
`:` (so `--env db.host=local` and `--env log:level=debug` work). A bare `-KEY` deletes that key from
the accumulated hash. `Hash` flags do not take `delimiter:`.

### Reject the `-key` delete form on a map

```crystal
flag define : Hash(String, String) = {} of String => String, "--define", "Build constant", hash_operations: false
```

`hash_operations: false` turns the bare `-KEY` delete form into a parse error, so a `-FOO` typo of
`FOO=...` is loud instead of a silent no-op. Assignment still works.

### Validate or transform each item of a list

```crystal
flag ports : Array(Int32) = [] of Int32, "--ports", "...", delimiter: ",", validate_with: :check_port
flag map : Array(Tuple(String, String)) = [] of Tuple(String, String), "--map", "SRC:DST", "...", delimiter: nil, transform_with: :parse_pair

def self.check_port(value : Int32) : Bool | String
  (1..65535).includes?(value) ? true : "port out of range: #{value}"
end

def self.parse_pair(value : String) : Tuple(String, String)
  a, _, b = value.partition(':')
  raise ArgumentError.new("expected SRC:DST") if b.empty?
  {a, b}
end
```

`transform_with:` and `validate_with:` apply per element on `Array`/`Set`/`Hash` flags, just like on
a scalar. This is how you accept an element type the shard has no built-in parser for (a
`Tuple(String, String)` for a `SRC:DST` flag); a bad item is rejected at parse time with the flag's
name in the message.

### Accept `--include` / `--exclude` keeping their exact order

```crystal
property rules : Array(Tuple(String, String)) = [] of Tuple(String, String)

ordered_flag_group "Filter rules (applied in command-line order)",
  {"--include" => "PATTERN: include matching files",
   "--exclude" => "PATTERN: exclude matching files"} do |key, value|
  @rules << {key, value} # key arrives with "--" stripped
end
```

`ordered_flag_group` is for the rsync/tar shape where the *interleaving between different flags* is
the meaning. Each occurrence is delivered to the block in command-line order at parse time, with the
matched spelling (dashes stripped) and the value. Raising `ArgumentError` from the block becomes a
clean parse error. Members render in help and complete like ordinary flags. (Value-taking members
only; switch members are not yet supported.)

## Enums

### Accept one of an enum's values

```crystal
enum Format
  Table
  Json
  Yaml
end

flag format : Format = Format::Table, "--format", "Output format"
```

An `enum` flag parses case names (case-insensitive, kebab-aware, so `full-speed` → `FullSpeed`) and
shows them pipe-joined in help. A `@[Flags]` enum accepts comma-separated values (`--perms
read,write`).

### Generate a switch for each enum value

```crystal
flag log_level : Format = Format::Table, "--log-level", "Log level", shortcut_flags: true
```

`shortcut_flags: true` generates a `--<case>` switch for every constant (`--table`, `--json`, ...),
each forcing that value. Last one wins, so `--json --yaml` resolves to `Yaml`.

### Exclude some enum cases, or add aliases like `--quiet`

```crystal
flag log_level : Severity = Severity::Notice, "--log-level", "Log level",
  shortcut_flags: {
    except:  [:none],
    aliases: {quiet: :warn, verbose: :info},
  }
```

The configured form controls generation: `only:` / `except:` pick which cases get switches (mutually
exclusive), and `aliases:` adds named switches mapping to a specific case. Generated names
(`--warn`, `--quiet`,...) share the command's flag namespace, so an alias colliding with another
flag — including an inherited or imported one — is a compile error; rename the alias if so.

## Subcommands and shared flags

### Add subcommands

```crystal
Shell::AutoComplete.command Build, name: "build", description: "Build it" do
  def run; end
end

Shell::AutoComplete.command Tool, name: "tool", description: "..." do
  subcommand Build
end
```

`subcommand` registers a child command. Sub-subcommands nest arbitrarily. `tool build --help` routes
to the child's help; `tool --all-help` prints the whole tree.

### Give a subcommand alternate names, like `mv` for `move`

```crystal
Shell::AutoComplete.command Move,
  name: "move",
  aliases: ["mv", "rename"],
  description: "Move or rename a file" do
  def run; end
end

Shell::AutoComplete.command Files, name: "files", description: "..." do
  subcommand Move
end
```

`aliases:` lists extra names the command answers to. `files move`, `files mv`, and `files rename`
all route to `Move`; every alias is offered in completion and listed beside the canonical name in
help (`move, mv, rename`). A canonical name always wins over an alias, so an alias can't shadow
another subcommand's real name.

### Let a global flag appear before or after the subcommand

```crystal
flag verbose : Bool = false, "--verbose", "Verbose"   # on the parent
```

A routing command's own flags work on either side of the subcommand word: `tool --verbose build` and
`tool build --verbose` both parse, and `tool --init` (with subcommands present) runs the parent's
own `run`. Tokens after `--` never route.

### Share a flag across some subcommands

```crystal
Shell::AutoComplete.common_flag :format,
  format : Format = Format::Table, "--format", "Output format"

Shell::AutoComplete.command List, name: "list", description: "..." do
  import_flags :format
  def run; end
end
```

`common_flag` defines a reusable flag once, outside any command; `import_flags` pulls a chosen
subset into a command, where it behaves exactly as if declared there. Different commands import
different subsets — the replacement for defining throwaway base commands just to share flags. With
this in place, `tool --format json list` routes to `list` (which imported `--format`) while
`tool --format json status` is rejected at `status` (which did not); the shard learns each
subcommand's flag arities to route past a flag before the subcommand word.

Declare the catalog at the top level, not inside a `module`: `common_flag` defines its replay macro
where it expands and `import_flags` resolves it from the command class, so nesting it makes it
invisible even to commands in the same module.

### Share global flags with every subcommand

```crystal
Shell::AutoComplete.command Base, name: "tool", description: "..." do
  flag host : String = "localhost", "--host", "Server"
end

Shell::AutoComplete.command Deploy, name: "deploy", description: "...", parent: Base do
  def run
    # host is available here
  end
end
```

`parent:` makes a command inherit every flag the parent declares — they become real properties,
parse, complete, and render under an `Inherited options` heading in the child's help. Inheritance
chains through multiple levels and composes with (but is independent of) `subcommand` routing.

### Run setup once before the command, like opening a connection or resolving `--color`

```crystal
flag dsn : String?, "--dsn", "Database URL"
getter! pool : DB::Database

before_run do
  target = dsn || ENV["DATABASE_URL"]? || raise ArgumentError.new("no --dsn and DATABASE_URL unset")
  @pool = DB.open(target)
end
```

`before_run` runs on the parsed instance after parsing and before `run` — the place for setup that
mutates shared state or can fail (open a connection, configure a global, resolve an inherited flag,
cross-flag validation). Raising `ArgumentError` becomes a clean parse error. Hooks are collected
down a `parent:` hierarchy and run parent-first, so every subcommand gets the base's setup without
calling `super`. For a value you only *read* (is color on?), a plain method is simpler than a hook:

```crystal
def color_enabled? : Bool
  case color
  in .always? then true
  in .never?  then false
  in .auto?   then STDOUT.tty?
  end
end
```

### Replace an inherited or shared flag at one command

```crystal
flag verbosity : Int32 = 0, "--verbose", "Verbosity level", override: true
```

`override: true` replaces a flag of the same spelling that came from `parent:` inheritance or
`import_flags` — all of the prior flag's spellings are freed and help/completion follow the
replacement. The overriding flag must bind a *new* property name (here `verbosity`, replacing a
`verbose` switch). Without `override:`, two flags claiming one spelling is a compile error.

## Help, version, and reference output

### Customize help layout

```crystal
Shell::AutoComplete.command Tool, name: "tool", description: "...",
  header: "tool — does things", footer: "See https://example.com",
  help_sections: [:subcommands, :options, :description] do
  flag host : String?, "--host", "Server", group: "Connection"
end
```

`header:`/`footer:` add prose around the output; `usage:` overrides the `Usage:` line.
`help_sections:` reorders or omits the middle sections (`:description`, `:options`, `:subcommands`,
`:positionals`). `group:` on a flag renders it under its own heading after the ungrouped options.

### Drive help text from a constant or method

```crystal
PRESETS     = %w[fast small balanced]
PRESET_HELP = "Encoder preset (one of: #{PRESETS.join(", ")})"

flag preset : String?, "--preset", PRESET_HELP, choices: PRESETS
```

Descriptions, headers, and footers accept a constant reference or a (no-argument) class-method
reference, so help text mirrors the constant that also drives validation. When the description would
directly follow the type declaration and Crystal reads the bare constant as a type, use the named
form: `flag x : String?, "--x", description: SOME_CONST`.

### Print the program name and version

```crystal
tool_version "1.4.0"
enable_version_subcommand
```

`--version` with no subcommand prints `<name> <version>` and exits. `tool_version` sets the string
(a plain string literal — no semantic-version parsing); without it, the shard uses the nearest
visible `VERSION` constant, else the project's `shards version` at build time. `tool_name` overrides
the name (default: the command name). `enable_version_subcommand` adds a `version` subcommand
printing the same line. Declaring your own `--version` flag, or `disable_version_flag`, turns the
intercept off.

### Print reference info and exit, like `--list-formats`

```crystal
flag list_formats : Bool = false, "--list-formats", "List formats and exit", immediate: :print_formats

def print_formats
  puts "table, json, yaml"
end
```

`immediate:` runs the handler the moment the flag appears, before the rest of the line is validated
— so an unrelated bad flag elsewhere does not suppress it. `immediate: :method` names the handler;
`immediate: true` uses the `immediate_<flag>` convention. Switch flags only.

## Completion and introspection

### Generate shell completion

```sh
mytool --shell-completion bash > /etc/bash_completion.d/mytool
mytool --shell-completion zsh  > ~/.zsh/completions/_mytool
mytool --shell-completion fish > ~/.config/fish/completions/mytool.fish
```

Every command gets `--shell-completion <shell>` for free. The script calls back into your binary for
candidates, so completion stays in sync with the parser — including subcommands, aliases, `@[Flags]`
trailing commas, and positional path completion.

### Provide dynamic completions for a flag

```crystal
flag branch : String?, "--branch", "Git branch", complete_with: :complete_branches

def self.complete_branches(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
  `git branch --format='%(refname:short)'`.lines.map(&.strip)
end
```

`complete_with:` names a class method that returns candidate strings; it is called at completion
time through your binary, so candidates can be computed live. The same works on a positional.

### Know whether a flag was given

```crystal
if flag_given?(:organized)
  # the user passed --organized or --no-organized explicitly
end
```

`flag_given?(:name)` reports whether a flag was set under any of its spellings, distinguishing an
explicit value (even one equal to the default) from absence. An unknown name raises `ArgumentError`.

### Recover the exact command line the user typed

```crystal
parsed_occurrences.each do |spelling, value|
  # spelling is "--include" / "-f" / "--no-color" exactly as typed
  # value is the raw argument, or nil for switches
end
```

`parsed_occurrences` is an ordered log of every flag occurrence — spelling as typed (aliases not
canonicalized) and raw value — for audit logging, re-emitting an equivalent command, or order-
sensitive resolution. It records flags only; positionals keep their own order separately.

## Errors

### Handle parse errors yourself

```crystal
begin
  MyTool.dispatch(ARGV, rescue_errors: false)
rescue ex : Shell::AutoComplete::ParseError
  STDERR.puts "fatal: #{ex.message}"
  exit 2
end
```

By default `dispatch` catches `ParseError`, prints `tool: <message>` to stderr, and exits 1. Pass
`rescue_errors: false` to let it raise so you can format or exit your own way. `ex.command_path`
carries the full subcommand path that failed.
