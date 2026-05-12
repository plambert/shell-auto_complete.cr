require "../../src/shell-auto_complete"

Shell::AutoComplete.command DeployCli, name: "deploy",
                            description: "Deploy an application" do
  flag name : String = "", "--name", "-n",
    "Deployment name (lowercase kebab-case, 1-40 chars)",
    validate_with: :validate_name

  flag region : String = "", "--region", "-r",
    "AWS region",
    validate_with: :validate_region,
    complete_with: :complete_region

  flag branch : String?, "--branch", "-b",
    "Git branch to deploy",
    complete_with: :complete_branch

  flag duration : Int32 = 600, "--duration", "-d",
    "Deployment timeout (e.g. 30s, 5m, 2h, 1d)",
    transform_with: :transform_duration

  flag size : Int64 = 0_i64, "--size", "-s",
    "Maximum artifact size (e.g. 512B, 2KB, 100MB, 1GB)",
    transform_with: :transform_size

  flag dry_run : Bool = false, "--dry-run",
    "Show what would happen without performing the deployment"

  ALLOWED_REGIONS  = %w[us-east-1 us-west-2 eu-west-1 ap-southeast-1]
  ALLOWED_BRANCHES = %w[main develop staging feature-x release-1.0]

  # --- Custom validators ---

  def self.validate_name(value : String) : Bool | String
    return "name must be 1-40 characters" unless (1..40).includes?(value.size)
    return "name must be lowercase kebab-case (a-z, 0-9, -); got: #{value}" unless value =~ /\A[a-z][a-z0-9-]*\z/
    true
  end

  def self.validate_region(value : String) : Bool | String
    if ALLOWED_REGIONS.includes?(value)
      true
    else
      "region must be one of #{ALLOWED_REGIONS.join(", ")}; got: #{value}"
    end
  end

  # --- Custom completers ---

  def self.complete_region(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
    ALLOWED_REGIONS
  end

  def self.complete_branch(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
    ALLOWED_BRANCHES
  end

  # --- Custom transformers ---

  def self.transform_duration(value : String) : Int32
    if m = value.match(/\A(?<n>\d+)(?<u>[smhd])\z/)
      n = m["n"].to_i
      case m["u"]
      when "s" then n
      when "m" then n * 60
      when "h" then n * 3600
      when "d" then n * 86400
      else          n
      end
    elsif value =~ /\A\d+\z/
      value.to_i  # bare number = seconds
    else
      raise ArgumentError.new("invalid duration: #{value} (use Ns, Nm, Nh, Nd)")
    end
  end

  def self.transform_size(value : String) : Int64
    if m = value.match(/\A(?<n>\d+(?:\.\d+)?)(?<u>B|KB|MB|GB|TB)?\z/i)
      n = m["n"].to_f64
      multiplier = case m["u"]?.try(&.upcase)
                   when "B", nil then 1_i64
                   when "KB"     then 1024_i64
                   when "MB"     then 1024_i64 * 1024
                   when "GB"     then 1024_i64 * 1024 * 1024
                   when "TB"     then 1024_i64 * 1024 * 1024 * 1024
                   else               1_i64
                   end
      (n * multiplier).to_i64
    else
      raise ArgumentError.new("invalid size: #{value} (use NB, NKB, NMB, NGB, NTB)")
    end
  end

  def run
    if name.empty?
      STDERR.puts "error: --name is required"
      exit 1
    end
    if region.empty?
      STDERR.puts "error: --region is required"
      exit 1
    end
    puts "Deployment plan:"
    puts "  name:     #{name}"
    puts "  region:   #{region}"
    puts "  branch:   #{branch || "(default)"}"
    puts "  duration: #{duration}s (#{format_duration(duration)})"
    puts "  size cap: #{size} bytes (#{format_size(size)})"
    puts
    if dry_run
      puts "[dry-run] Would deploy."
    else
      puts "Deploying..."
    end
  end

  private def format_duration(seconds : Int32) : String
    return "#{seconds // 86400}d" if seconds >= 86400 && seconds % 86400 == 0
    return "#{seconds // 3600}h" if seconds >= 3600 && seconds % 3600 == 0
    return "#{seconds // 60}m" if seconds >= 60 && seconds % 60 == 0
    "#{seconds}s"
  end

  private def format_size(bytes : Int64) : String
    return "0B" if bytes == 0
    units = %w[B KB MB GB TB]
    n = bytes.to_f64
    i = 0
    while n >= 1024 && i < units.size - 1
      n /= 1024
      i += 1
    end
    "%.2f%s" % [n, units[i]]
  end
end

DeployCli.dispatch(ARGV)
