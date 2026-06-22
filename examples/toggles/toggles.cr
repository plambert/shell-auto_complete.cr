require "../../src/shell-auto_complete"

# toggles — a feature-flag / config management CLI.
#
# This example is the introspection & config showcase for shell-auto_complete.
# It demonstrates SetDelta deltas, dotted/colon Hash keys, Bool? tri-state with
# flag_given?, a shared common_flag overridden at the leaf command, a
# constant-reference flag description, and a disabled --version intercept.

# Top-level constant used as a flag description below. Passing it via the
# `description:` named option keeps the parser from mistaking a bare CONSTANT
# (after the type) for the description-by-position string.
MODE_HELP = <<-TEXT.gsub('\n', ' ')
  Rollout mode for the changed flags: how aggressively to ship them.
  One of strict, canary, or wide.
  TEXT

MODES = %w[strict canary wide]

# A common_flag catalog entry: a plain Bool --verbose switch. It is imported
# into the base command below, then replaced at the leaf with an Int32 level
# via override: true.
Shell::AutoComplete.common_flag :verbosity,
  verbose : Bool = false, "--verbose", "-v", "Verbose output"

# ---------------------------------------------------------------------------
# Base command: holds the shared --verbose switch from the catalog. `toggles`
# inherits from it via `parent:`. It is never dispatched directly.
# ---------------------------------------------------------------------------
Shell::AutoComplete.command TogglesBase,
  name: "toggles-base",
  description: "Shared flags for the toggles tool" do
  import_flags :verbosity
end

# ---------------------------------------------------------------------------
# toggles — apply a set delta to the feature-flag set, set config keys, and
# report the tri-state "organized" preference.
# ---------------------------------------------------------------------------
Shell::AutoComplete.command Toggles,
  name: "toggles",
  description: "Manage feature flags and configuration",
  parent: TogglesBase do
  # --version is intentionally off: a bare `toggles +version` is a feature-flag
  # delta (enable a flag named "version"), not a version request, so claiming
  # --version here would be surprising. The tool reports its build elsewhere.
  disable_version_flag

  # Replace the inherited Bool --verbose (from the imported :verbosity catalog
  # entry) with an Int32 level. override: true is required because --verbose is
  # already claimed; the new property name must differ from the replaced one.
  flag verbose_level : Int32 = 0, "--verbose", "-v",
    "Verbosity level (0-3)", range: 0..3, override: true

  # Hash flag whose keys may contain dots and colons (db.host, log:level).
  # Bare `-key` deletes a key from the accumulated hash (hash_operations
  # defaults to true).
  flag set : Hash(String, String) = {} of String => String, "--set",
    "KEY=VALUE", "Set a config key (keys may contain . and :)"

  # A second Hash flag with hash_operations: false, so the bare `-key` delete
  # form is a parse error here — only KEY=VALUE assignment is accepted.
  flag define : Hash(String, String) = {} of String => String, "--define", "-D",
    "KEY=VALUE", "Define a build constant (assignment only; -key is rejected)",
    hash_operations: false

  # Tri-state preference: nil (absent), true (--organized), false
  # (--no-organized). flag_given?(:organized) distinguishes "absent" from an
  # explicit --no-organized in run.
  flag organized : Bool?, "--organized", "Group flags by namespace in output"

  # Constant-reference description via the named `description:` option.
  flag mode : String?, "--mode", description: MODE_HELP, choices: MODES

  # The set delta. Tokens are +name (enable), bare name (enable), -name
  # (disable). Because SetDelta is in play, single-dash tokens like -telemetry
  # parse as positionals, not flags. Binds Hash(String, Bool); at least one
  # token is required.
  positionals changes : Shell::AutoComplete::Types::SetDelta,
    "+name to enable, -name to disable", min: 1

  # The seed set of currently-enabled flags this tool starts from.
  SEED = Set{"dark-mode", "telemetry", "beta"}

  def run
    seed = SEED.dup
    enabled = Shell::AutoComplete::Types::SetDelta.apply(seed, changes)

    puts "feature flags:"
    SEED.each do |name|
      next if enabled.includes?(name)
      puts "  - #{name} (disabled)"
    end
    enabled.to_a.sort.each do |name|
      marker = SEED.includes?(name) ? " " : "+"
      puts "  #{marker} #{name} (enabled)"
    end

    puts
    puts "config (--set):"
    if set.empty?
      puts "  (none)"
    else
      set.to_a.sort_by(&.first).each { |k, v| puts "  #{k} = #{v}" }
    end

    puts
    puts "build constants (--define):"
    if define.empty?
      puts "  (none)"
    else
      define.to_a.sort_by(&.first).each { |k, v| puts "  #{k} = #{v}" }
    end

    puts
    print "organized: "
    if flag_given?(:organized)
      puts organized ? "on (explicit --organized)" : "off (explicit --no-organized)"
    else
      puts "unset (flag absent; using default grouping)"
    end

    puts "mode:      #{mode || "(default)"}"
    puts "verbose:   level #{verbose_level}"
    if verbose_level >= 2
      puts "(verbose) seed flags were: #{SEED.to_a.sort.join(", ")}"
    end
  end
end

Toggles.dispatch(ARGV)
