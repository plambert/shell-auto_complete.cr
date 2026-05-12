require "../../src/shell-auto_complete"

# ---------------------------------------------------------------------------
# Enums used by the transform subcommand
# ---------------------------------------------------------------------------

enum LogLevel
  Debug
  Info
  Warn
  Error
  Fatal
end

@[Flags]
enum Perm
  Read
  Write
  Execute
end

# ---------------------------------------------------------------------------
# scan deep — numeric scalars + synthetic PositiveInt / NonNegativeInt
# ---------------------------------------------------------------------------

Shell::AutoComplete.command MultitoolScanDeep,
  name: "deep",
  description: "Deep scan: numeric scalars and constrained integer types" do
  flag int8 : Int8?, "--int8", "Signed 8-bit integer"
  flag int16 : Int16?, "--int16", "Signed 16-bit integer"
  flag int32 : Int32?, "--int32", "Signed 32-bit integer"
  flag int64 : Int64?, "--int64", "Signed 64-bit integer"
  flag uint8 : UInt8?, "--uint8", "Unsigned 8-bit integer"
  flag uint16 : UInt16?, "--uint16", "Unsigned 16-bit integer"
  flag uint32 : UInt32?, "--uint32", "Unsigned 32-bit integer"
  flag uint64 : UInt64?, "--uint64", "Unsigned 64-bit integer"
  flag float32 : Float32?, "--float32", "32-bit float"
  flag float64 : Float64?, "--float64", "64-bit float"

  flag positive_int : Int32?, "--positive-int", "Strictly positive integer (>0)",
    transform_with: :transform_positive_int,
    validate_with: :validate_positive_int

  flag non_negative_int : Int32?, "--non-negative-int", "Non-negative integer (>=0)",
    transform_with: :transform_non_negative_int,
    validate_with: :validate_non_negative_int

  def self.transform_positive_int(value : String) : Int32
    Shell::AutoComplete::Types::PositiveInt.__arg_transform(value)
  end

  def self.validate_positive_int(value : Int32) : Bool | String
    Shell::AutoComplete::Types::PositiveInt.__arg_validate(value)
  end

  def self.transform_non_negative_int(value : String) : Int32
    Shell::AutoComplete::Types::NonNegativeInt.__arg_transform(value)
  end

  def self.validate_non_negative_int(value : Int32) : Bool | String
    Shell::AutoComplete::Types::NonNegativeInt.__arg_validate(value)
  end

  def run
    puts "=== scan deep ==="
    puts "  --int8           #{int8.inspect}"
    puts "  --int16          #{int16.inspect}"
    puts "  --int32          #{int32.inspect}"
    puts "  --int64          #{int64.inspect}"
    puts "  --uint8          #{uint8.inspect}"
    puts "  --uint16         #{uint16.inspect}"
    puts "  --uint32         #{uint32.inspect}"
    puts "  --uint64         #{uint64.inspect}"
    puts "  --float32        #{float32.inspect}"
    puts "  --float64        #{float64.inspect}"
    puts "  --positive-int   #{positive_int.inspect}"
    puts "  --non-negative-int #{non_negative_int.inspect}"
  end
end

# ---------------------------------------------------------------------------
# scan quick — string/char/bool scalars + synthetic Percentage/EpochTime/Date
# ---------------------------------------------------------------------------

Shell::AutoComplete.command MultitoolScanQuick,
  name: "quick",
  description: "Quick scan: string/char/bool and date/time synthetic types" do
  flag string : String?, "--string", "-s", "Arbitrary string value"
  flag char : Char?, "--char", "-c", "Single character"
  flag bool : Bool = false, "--bool", "-b", "Boolean flag (negatable)"

  flag percentage : Float64?, "--percentage", "Percentage value (0.0–100.0)",
    transform_with: :transform_percentage,
    validate_with: :validate_percentage

  flag epoch_time : Time?, "--epoch-time", "Unix epoch seconds → Time",
    transform_with: :transform_epoch_time,
    validate_with: :validate_epoch_time

  flag date : Time?, "--date", "-d", "Date in YYYY-MM-DD format → Time",
    transform_with: :transform_date,
    validate_with: :validate_date

  def self.transform_percentage(value : String) : Float64
    Shell::AutoComplete::Types::Percentage.__arg_transform(value)
  end

  def self.validate_percentage(value : Float64) : Bool | String
    Shell::AutoComplete::Types::Percentage.__arg_validate(value)
  end

  def self.transform_epoch_time(value : String) : Time
    Shell::AutoComplete::Types::EpochTime.__arg_transform(value)
  end

  def self.validate_epoch_time(value : Time) : Bool | String
    Shell::AutoComplete::Types::EpochTime.__arg_validate(value)
  end

  def self.transform_date(value : String) : Time
    Shell::AutoComplete::Types::Date.__arg_transform(value)
  end

  def self.validate_date(value : Time) : Bool | String
    Shell::AutoComplete::Types::Date.__arg_validate(value)
  end

  def run
    puts "=== scan quick ==="
    puts "  --string      #{string.inspect}"
    puts "  --char        #{char.inspect}"
    puts "  --bool        #{bool}"
    puts "  --percentage  #{percentage.inspect}"
    puts "  --epoch-time  #{epoch_time.inspect}"
    puts "  --date        #{date.inspect}"
  end
end

# ---------------------------------------------------------------------------
# scan — routing subcommand (no flags of its own)
# ---------------------------------------------------------------------------

Shell::AutoComplete.command MultitoolScan,
  name: "scan",
  description: "Scan subcommand — choose deep or quick" do
  subcommand MultitoolScanDeep
  subcommand MultitoolScanQuick
end

# ---------------------------------------------------------------------------
# transform — collections + enums
# ---------------------------------------------------------------------------

Shell::AutoComplete.command MultitoolTransform,
  name: "transform",
  description: "Transform: collection types and enums" do
  flag tags : Array(String) = [] of String, "--tags", "-t",
    "Comma-separated string tags (Array(String))"

  flag ints : Array(Int32) = [] of Int32, "--ints", "-i",
    "Comma-separated integers (Array(Int32))"

  flag levels : Set(String) = Set(String).new, "--levels", "-l",
    "Comma-separated level strings (Set(String))"

  flag env : Hash(String, String) = {} of String => String, "--env", "-e",
    "KEY=VALUE environment entries (Hash(String, String))"

  flag log_level : LogLevel = LogLevel::Info, "--log-level", "-L",
    "Log level (Debug/Info/Warn/Error/Fatal)", shortcut_flags: true

  flag perms : Perm = Perm::None, "--perms", "-p",
    "Permission bits: read,write,execute (@[Flags] enum)"

  def run
    puts "=== transform ==="
    puts "  --tags       #{tags.inspect}"
    puts "  --ints       #{ints.inspect}"
    puts "  --levels     #{levels.inspect}"
    puts "  --env        #{env.inspect}"
    puts "  --log-level  #{log_level}"
    puts "  --perms      #{perms}"
  end
end

# ---------------------------------------------------------------------------
# config get — path/filesystem + regex
# ---------------------------------------------------------------------------

Shell::AutoComplete.command MultitoolConfigGet,
  name: "get",
  description: "Config get: path and regex types" do
  flag path : Path?, "--path", "-p", "Filesystem path (Path)"
  flag file : Path?, "--file", "-f", "Existing regular file (File → Path)",
    transform_with: :transform_file
  flag dir : Path?, "--dir", "-d", "Existing directory (Dir → Path)",
    transform_with: :transform_dir
  flag regex : Regex?, "--regex", "-r", "Regular expression (Regex)"

  def self.transform_file(value : String) : Path
    File.__arg_transform(value)
  end

  def self.transform_dir(value : String) : Path
    Dir.__arg_transform(value)
  end

  def run
    puts "=== config get ==="
    puts "  --path   #{path.inspect}"
    puts "  --file   #{file.inspect}"
    puts "  --dir    #{dir.inspect}"
    puts "  --regex  #{regex.inspect}"
  end
end

# ---------------------------------------------------------------------------
# config set — stdlib types + synthetic EnvVar
# ---------------------------------------------------------------------------

Shell::AutoComplete.command MultitoolConfigSet,
  name: "set",
  description: "Config set: URI, Time, Socket::IPAddress, Log::Severity, EnvVar" do
  flag url : URI?, "--url", "-u", "URL / URI"
  flag time : Time?, "--time", "-T", "Timestamp (ISO 8601 or RFC 2822)"
  flag ip : Socket::IPAddress?, "--ip", "-i", "IP address with optional port (host:port)"
  flag severity : Log::Severity?, "--severity", "-S", "Log severity level"

  flag env_var : String?, "--env-var", "-e", "Environment variable name (validated)",
    transform_with: :transform_env_var,
    validate_with: :validate_env_var

  def self.transform_env_var(value : String) : String
    Shell::AutoComplete::Types::EnvVar.__arg_transform(value)
  end

  def self.validate_env_var(value : String) : Bool | String
    Shell::AutoComplete::Types::EnvVar.__arg_validate(value)
  end

  def run
    puts "=== config set ==="
    puts "  --url      #{url.inspect}"
    puts "  --time     #{time.inspect}"
    puts "  --ip       #{ip.inspect}"
    puts "  --severity #{severity.inspect}"
    puts "  --env-var  #{env_var.inspect}"
  end
end

# ---------------------------------------------------------------------------
# config — routing subcommand
# ---------------------------------------------------------------------------

Shell::AutoComplete.command MultitoolConfig,
  name: "config",
  description: "Config subcommand — choose get or set" do
  subcommand MultitoolConfigGet
  subcommand MultitoolConfigSet
end

# ---------------------------------------------------------------------------
# Root command
# ---------------------------------------------------------------------------

Shell::AutoComplete.command Multitool,
  name: "multitool",
  description: "Demo CLI exercising every bundled transformer and synthetic type" do
  subcommand MultitoolScan
  subcommand MultitoolTransform
  subcommand MultitoolConfig
end

Multitool.dispatch(ARGV)
