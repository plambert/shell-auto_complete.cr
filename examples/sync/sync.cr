require "../../src/shell-auto_complete"

# An rsync-style file sync CLI. This example is the ordering & validation
# showcase: include/exclude filter rules whose command-line ORDER is the
# semantics, custom per-element transforms, range/regex/choice validation,
# Set arithmetic, an immediate "print and exit" switch, and reconstruction
# of the original invocation from parsed_occurrences.
Shell::AutoComplete.command SyncCli, name: "sync",
  description: "Synchronize files from source(s) to a destination (rsync-style)" do
  # --- include / exclude filter rules ---------------------------------------
  # The ORDER between --include and --exclude matters: the first matching rule
  # wins, exactly as rsync treats its filter list. The ordered_flag_group block
  # records each occurrence into @rules at parse time, in argv order.
  property rules : Array(Tuple(String, String)) = [] of Tuple(String, String)

  ordered_flag_group "Filter rules (applied in command-line order, first match wins)",
    {"--include" => "PATTERN: include files matching the glob",
     "--exclude" => "PATTERN: exclude files matching the glob"} do |key, value|
    raise ArgumentError.new("filter pattern may not be empty") if value.empty?
    @rules << {key, value}
  end

  # --- value-taking, validated flags ----------------------------------------

  # choices: restricts the accepted values; help shows none|md5|sha256.
  flag checksum : String = "none", "--checksum", "-c",
    "Integrity check algorithm",
    choices: %w[none md5 sha256]

  # range: a numeric bound (bytes/sec; 0 means unlimited).
  flag bwlimit : Int64 = 0_i64, "--bwlimit", "-b",
    "Bandwidth limit in bytes/sec (0 = unlimited)",
    range: (0_i64..1_000_000_i64)

  # matches: the value must satisfy this regex (a sed-style s/old/new/ rule).
  flag rename : String?, "--rename",
    "Rename rule, e.g. s/old/new/",
    matches: /\As\/[^\/]*\/[^\/]*\/\z/

  # set_operations: --with accepts +name / -name / name tokens and folds them
  # into a Set, honoring the delimiter for one-shot comma lists.
  flag with : Set(String) = Set(String).new, "--with", "-w",
    "Optional features to toggle (e.g. +delete,-perms)",
    delimiter: ",", set_operations: true

  # Embedded value placeholder: "--max-size SIZE" puts SIZE in the help text.
  flag max_size : Int64 = 0_i64, "--max-size SIZE", "-m",
    "Skip files larger than SIZE bytes (0 = no limit)",
    range: (0_i64..Int64::MAX)

  # Explicit placeholder: for the dest-suffix tag shown in help as TAG.
  flag suffix : String?, "--suffix",
    "Backup suffix for replaced files",
    placeholder: "TAG"

  # Per-element transform on a collection: each --map takes one SRC:DST and is
  # parsed by parse_mapping into a tuple. delimiter: nil disables list splitting
  # so a literal ':' in a value is unambiguous.
  flag map : Array(Tuple(String, String)) = [] of Tuple(String, String), "--map", "SRC:DST",
    "Path rewrite mapping, repeatable",
    delimiter: nil, transform_with: :parse_mapping

  # immediate: prints the filter syntax and exits before full validation.
  flag list_filters : Bool = false, "--list-filters",
    "Print the filter rule syntax and exit",
    immediate: :print_filters

  flag dry_run : Bool = false, "--dry-run", "-n",
    "Show what would be transferred without copying"

  # SRC... DEST — at least two paths; the last is the destination.
  positionals paths : Array(Path), "SRC... DEST", min: 2

  # --- class methods referenced by flag options -----------------------------

  # Splits "SRC:DST" into a tuple; raises ArgumentError on malformed input,
  # which the framework converts to a ParseError naming the flag.
  def self.parse_mapping(value : String) : Tuple(String, String)
    parts = value.split(':', 2)
    unless parts.size == 2 && !parts[0].empty? && !parts[1].empty?
      raise ArgumentError.new("mapping must be SRC:DST with both sides non-empty; got #{value.inspect}")
    end
    {parts[0], parts[1]}
  end

  # --- immediate handler (instance method) ----------------------------------

  def print_filters
    puts "Filter rules are evaluated in command-line order; the first match wins."
    puts
    puts "  --include PATTERN   include files matching the glob PATTERN"
    puts "  --exclude PATTERN   exclude files matching the glob PATTERN"
    puts
    puts "Example:"
    puts "  sync --include '*.rb' --exclude 'test/*' --include 'lib/*' src dst"
    puts
    puts "PATTERN is a shell glob (*, ?, [..]); '/' separates path components."
  end

  # --- run -------------------------------------------------------------------

  def run
    src = paths[0...-1].map(&.to_s)
    dest = paths[-1].to_s

    puts "Sync configuration:"
    puts "  sources:   #{src.join(", ")}"
    puts "  dest:      #{dest}"
    puts "  checksum:  #{checksum}"
    puts "  bwlimit:   #{bwlimit == 0 ? "unlimited" : "#{bwlimit} B/s"}"
    puts "  max-size:  #{max_size == 0 ? "no limit" : "#{max_size} B"}"
    puts "  rename:    #{rename || "(none)"}"
    puts "  suffix:    #{suffix || "(none)"}"
    features = self.with
    puts "  with:      #{features.empty? ? "(none)" : features.to_a.sort.join(", ")}"
    puts "  dry-run:   #{dry_run}"

    puts
    if rules.empty?
      puts "Filter rules: (none — transfer everything)"
    else
      puts "Filter rules (in order):"
      rules.each_with_index(1) do |(action, pattern), index|
        verb = action == "include" ? "include" : "exclude"
        puts "  #{index}. #{verb} #{pattern}"
      end
    end

    puts
    if map.empty?
      puts "Path mappings: (none)"
    else
      puts "Path mappings:"
      map.each do |(from, to)|
        puts "  #{from} -> #{to}"
      end
    end

    # Reconstruct an equivalent command from parsed_occurrences, preserving the
    # exact order the flags were typed. parsed_occurrences records flag
    # occurrences (spelling-as-typed plus raw value); positionals are appended
    # afterward to round out the recovered invocation.
    reemit = String.build do |str|
      str << "sync"
      parsed_occurrences.each do |spelling, value|
        str << ' ' << spelling
        if raw = value
          str << ' ' << Process.quote(raw)
        end
      end
      paths.each { |path| str << ' ' << Process.quote(path.to_s) }
    end
    puts
    puts "Re-emit (recovered from parsed_occurrences):"
    puts "  #{reemit}"
  end
end

SyncCli.dispatch(ARGV)
