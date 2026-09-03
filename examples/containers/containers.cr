require "../../src/shell-auto_complete"

# A docker/podman-style container CLI.
#
# This example is the dispatch-and-sharing showcase. It demonstrates:
#
#   * a base command holding global flags that subcommands inherit via `parent:`
#   * a `before_run` hook on the base that resolves `--host` (or an env var)
#     into a shared connection string, raising `ArgumentError` (→ clean parse
#     error) when it can't
#   * a `common_flag` catalog pulled into commands with `import_flags`, where
#     different subcommands import different subsets
#   * the routing-union: `containers --format json ps` routes, but
#     `containers --format json rm` is rejected because `rm` imports no
#     `--format`
#   * `--version` via `tool_version` plus a `version` subcommand
#   * `shortcut_flags` configuration on an enum flag (`--log-level`), including
#     short spellings for both a generated case switch and an alias
#   * a `group:` heading on the connection flags and `help_sections:` reordering
#   * explicit and type-derived value placeholders

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum OutputFormat
  Table
  Json
  Yaml
end

enum LogLevel
  None
  Error
  Warn
  Info
  Debug
end

# ---------------------------------------------------------------------------
# Shared listing flags — a named catalog declared once, imported per command.
# Each importing command gets its own copy: it registers in that command's
# name table, shows up in its help, and completes like a directly-declared flag.
# ---------------------------------------------------------------------------

Shell::AutoComplete.common_flag :format,
  format : OutputFormat = OutputFormat::Table, "--format", "Output format"

Shell::AutoComplete.common_flag :filter,
  filter : Array(String) = [] of String, "--filter", "-f",
  "Filter output (e.g. status=running); repeatable", delimiter: nil

Shell::AutoComplete.common_flag :quiet,
  quiet : Bool = false, "--quiet", "-q", "Only display IDs"

Shell::AutoComplete.common_flag :all,
  all : Bool = false, "--all", "-a", "Show all (default shows just running)"

Shell::AutoComplete.common_flag :digests,
  digests : Bool = false, "--digests", "Show image digests"

# ---------------------------------------------------------------------------
# Base command — global flags, the connection-resolving hook, version config.
# Subcommands inherit all of this through `parent: Containers`.
# ---------------------------------------------------------------------------

Shell::AutoComplete.command Containers,
  name: "containers",
  description: "Manage containers and images on a local or remote daemon",
  footer: "Run 'containers COMMAND --help' for more information on a command." do
  tool_version "1.4.0"
  enable_version_subcommand

  flag host : String?, "--host", "-H", "HOST[:PORT]",
    "Daemon socket or host to connect to (env: CONTAINER_HOST)",
    group: "Connection options"

  flag debug : Bool = false, "--debug",
    "Enable debug-level client logging",
    group: "Connection options"

  flag log_level : LogLevel = LogLevel::Warn, "--log-level", "-l",
    "Client log level",
    group: "Connection options",
    shortcut_flags: {
      except:  [:none, :debug],
      shorts:  {warn: "-w"},
      aliases: {
        silent:  {value: :warn, short: "-s", description: "Log warnings and errors only"},
        verbose: {value: :info, short: "-v"},
      },
    }

  # Resolved connection string, shared with every inheriting subcommand.
  property conn : String = ""

  # Runs after parse, before run, parent-first for inherited subcommands.
  before_run do
    target = host || ENV["CONTAINER_HOST"]?
    raise ArgumentError.new(
      "no daemon: pass --host or set CONTAINER_HOST") if target.nil? || target.empty?

    @conn = target.includes?("://") ? target : "tcp://#{target}"
  end

  # The bare `containers` command just reports the resolved connection.
  def run
    puts "Connected to #{conn}"
    puts "  log level: #{log_level}"
    puts "  debug:     #{debug}"
    puts
    puts "Run 'containers --help' to see available commands."
  end
end

# ---------------------------------------------------------------------------
# ps — list containers. Imports format/filter/quiet/all (no digests).
# Because it declares --format, the routing-union lets `--format` appear
# before `ps` on the base command line.
# ---------------------------------------------------------------------------

Shell::AutoComplete.command ContainersPs,
  name: "ps",
  description: "List containers",
  parent: Containers,
  help_sections: [:description, :options, :positionals, :subcommands] do
  import_flags :format, :filter, :quiet, :all

  def run
    puts "ps on #{conn}"
    puts "  format:  #{format}"
    puts "  filters: #{filter.inspect}"
    puts "  quiet:   #{quiet}"
    puts "  all:     #{all}"
  end
end

# ---------------------------------------------------------------------------
# images — list images. Imports a different subset: format/filter/quiet/digests.
# It too declares --format, so `containers --format json images` routes.
# ---------------------------------------------------------------------------

Shell::AutoComplete.command ContainersImages,
  name: "images",
  description: "List images",
  parent: Containers do
  import_flags :format, :filter, :quiet, :digests

  def run
    puts "images on #{conn}"
    puts "  format:  #{format}"
    puts "  filters: #{filter.inspect}"
    puts "  quiet:   #{quiet}"
    puts "  digests: #{digests}"
  end
end

# ---------------------------------------------------------------------------
# rm — remove containers. Imports NO listing flags, so `--format` is unknown
# here: `containers --format json rm` is rejected at rm.
# ---------------------------------------------------------------------------

Shell::AutoComplete.command ContainersRm,
  name: "rm",
  description: "Remove one or more containers",
  parent: Containers do
  flag force : Bool = false, "--force",
    "Force removal of a running container (uses SIGKILL)"

  flag signal : String = "SIGTERM", "--signal SIGNAL",
    "Signal to send to the container before removal"

  positionals names : Array(String),
    "Containers to remove (name or ID)"

  def run
    puts "rm on #{conn}"
    puts "  force:   #{force}"
    puts "  signal:  #{signal}"
    puts "  targets: #{names.inspect}"
  end
end

# ---------------------------------------------------------------------------
# Routing — declared on the base. Inheritance (parent:) and routing
# (subcommand) compose but are independent.
# ---------------------------------------------------------------------------

class Containers
  subcommand ContainersPs
  subcommand ContainersImages
  subcommand ContainersRm
end

Containers.dispatch(ARGV)
