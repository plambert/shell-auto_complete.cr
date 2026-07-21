require "../spec_helper"

# Flag-side twin of file_dir_positional_spec / positional_complete_spec
# (issue #48): value completion for flags must be derived from the flag's
# declared type, and a value-taking flag with no derived completion must
# offer nothing — never flag names.

private FV_FILES = Shell::AutoComplete::Completion::Directive::FILES
private FV_DIRS  = Shell::AutoComplete::Completion::Directive::DIRS

# Path/File/Dir flags, nilable and not, with aliases and short forms.
Shell::AutoComplete.command FvPaths, name: "fvpaths", description: "x" do
  flag pathflag : Path?, %w[--pathflag --path-alias], "-p", "a Path flag"
  flag fileflag : File?, "--fileflag", "-f", "a File flag"
  flag dirflag : Dir?, "--dirflag", "-d", "a Dir flag"
  flag reqpath : Path = Path.new("."), "--reqpath", "a defaulted non-nilable Path flag"

  def run
  end
end

# Types with no obvious completion: the value position must yield nothing.
Shell::AutoComplete.command FvPlain, name: "fvplain", description: "x" do
  flag count : Int32?, "--count", "-c"
  flag ratio : Float64?, "--ratio"
  flag label : String?, "--label", "-l"
  flag when_ : Time?, "--when"
  flag url : URI?, "--url"
  flag pattern : Regex?, "--pattern"
  flag initial : Char?, "--initial"
  flag verbose : Bool = false, "--verbose", "-v"

  def run
  end
end

# choices: on a String flag.
Shell::AutoComplete.command FvChoices, name: "fvchoices", description: "x" do
  flag format : String = "table", "--format", "-F", choices: ["json", "yaml", "table"]

  def run
  end
end

# choices: must lose to an explicit complete_with:.
Shell::AutoComplete.command FvChoicesCw, name: "fvchoicescw", description: "x" do
  flag format : String = "table", "--format", choices: ["json", "yaml"], complete_with: :formats

  def self.formats(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
    %w[custom-only]
  end

  def run
  end
end

# complete_with: must win over the derived path directive.
Shell::AutoComplete.command FvPathCw, name: "fvpathcw", description: "x" do
  flag output : Path?, "--output", complete_with: :outputs

  def self.outputs(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
    %w[a.log b.log]
  end

  def run
  end
end

enum FvUnit
  Bytes
  Kilobytes
  Megabytes
end

# Collection flags: element-type completion, with and without a delimiter.
Shell::AutoComplete.command FvColl, name: "fvcoll", description: "x" do
  flag inputs : Array(Path)?, "--input", "-i", delimiter: nil
  flag units : Array(FvUnit)?, "--unit", "-u", delimiter: ","
  flag unitset : Set(FvUnit)?, "--unitset", delimiter: ","
  flag joined : Array(Path)?, "--joined", delimiter: ","
  flag envs : Hash(String, String) = {} of String => String, "--env", "-e"

  def run
  end
end

@[Flags]
enum FvPerm
  Read
  Write
  Execute
end

Shell::AutoComplete.command FvFlagsEnum, name: "fvflagsenum", description: "x" do
  flag perms : FvPerm = FvPerm::None, "--perms", "-P"

  def run
  end
end

# @[Flags] enum with complete_with: — the explicit completer must win over
# derived member/trailing-comma candidates.
Shell::AutoComplete.command FvFlagsEnumCw, name: "fvflagsenumcw", description: "x" do
  flag perms : FvPerm = FvPerm::None, "--perms", complete_with: :perm_candidates

  def self.perm_candidates(ctx : Shell::AutoComplete::CompletionContext) : Array(String)
    %w[custom-perm]
  end

  def run
  end
end

# Ordered flag group: value-taking spellings with free-form values.
Shell::AutoComplete.command FvGroup, name: "fvgroup", description: "x" do
  property rules = [] of {String, String}

  ordered_flag_group "Filter rules",
    {"--include" => "PATTERN: include", "--exclude" => "PATTERN: exclude"} do |key, value|
    @rules << {key, value}
  end

  def run
  end
end

# EnvVar flag completes against the current environment.
Shell::AutoComplete.command FvEnv, name: "fvenv", description: "x" do
  flag var : Shell::AutoComplete::Types::EnvVar?, "--var"

  def run
  end
end

# A path flag alongside a path positional: the `--` terminator turns a
# flag-looking token into a positional, so the value branch must not engage.
Shell::AutoComplete.command FvMixed, name: "fvmixed", description: "x" do
  flag count : Int32?, "--count"
  positionals paths : Array(Path), "paths"

  def run
  end
end

# Enum-typed positionals: __arg_complete is inherited from the Enum base, so
# the metaclass-method existence check alone used to miss it.
Shell::AutoComplete.command FvEnumPos, name: "fvenumpos", description: "x" do
  positional first : FvUnit, "a unit"
  positionals rest : Array(FvUnit), "more units"

  def run
  end
end

private def fv_complete(klass, args : Array(String)) : Array(String)
  output = IO::Memory.new
  klass.dispatch(args, stdout: output)
  output.to_s.lines.map(&.strip).reject(&.empty?)
end

describe "flag values: Path/File/Dir flags emit the native directives (issue #48)" do
  it "Path flag emits the files directive after its canonical spelling" do
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "--pathflag", ""]).should eq([FV_FILES])
  end

  it "Path flag emits the files directive after an alias spelling" do
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "--path-alias", ""]).should eq([FV_FILES])
  end

  it "Path flag emits the files directive after its short form" do
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "-p", ""]).should eq([FV_FILES])
  end

  it "emits the directive with a partial value typed" do
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "--pathflag", "/tm"]).should eq([FV_FILES])
  end

  it "File flag emits the files directive" do
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "--fileflag", ""]).should eq([FV_FILES])
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "-f", ""]).should eq([FV_FILES])
  end

  it "Dir flag emits the dirs directive (not files)" do
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "--dirflag", ""]).should eq([FV_DIRS])
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "-d", ""]).should eq([FV_DIRS])
  end

  it "non-nilable Path flag emits the files directive" do
    fv_complete(FvPaths, ["__complete", "2", "fvpaths", "--reqpath", ""]).should eq([FV_FILES])
  end

  it "complete_with: wins over the derived path directive" do
    fv_complete(FvPathCw, ["__complete", "2", "fvpathcw", "--output", ""]).should eq(["a.log", "b.log"])
  end
end

describe "flag values: no derived completion means no candidates at all" do
  {"--count", "-c", "--ratio", "--label", "-l", "--when", "--url", "--pattern", "--initial"}.each do |spelling|
    it "offers nothing after #{spelling}" do
      fv_complete(FvPlain, ["__complete", "2", "fvplain", spelling, ""]).should be_empty
    end
  end

  it "offers nothing even when the value position starts with a dash" do
    # The parser consumes the next token as the value regardless of a leading
    # dash, so flag-name completion here would insert a flag name as the value.
    fv_complete(FvPlain, ["__complete", "2", "fvplain", "--count", "--"]).should be_empty
  end

  it "still completes flag names after a switch" do
    lines = fv_complete(FvPlain, ["__complete", "2", "fvplain", "--verbose", ""])
    lines.should contain("--count")
    lines.should contain("--label")
  end

  it "offers nothing for a Hash flag value" do
    fv_complete(FvColl, ["__complete", "2", "fvcoll", "--env", ""]).should be_empty
  end

  it "offers nothing after an ordered-flag-group spelling" do
    fv_complete(FvGroup, ["__complete", "2", "fvgroup", "--include", ""]).should be_empty
    fv_complete(FvGroup, ["__complete", "2", "fvgroup", "--exclude", ""]).should be_empty
  end
end

describe "flag values: choices:" do
  it "offers every choice at an empty value" do
    fv_complete(FvChoices, ["__complete", "2", "fvchoices", "--format", ""]).should eq(["json", "yaml", "table"])
  end

  it "prefix-filters choices" do
    fv_complete(FvChoices, ["__complete", "2", "fvchoices", "--format", "j"]).should eq(["json"])
  end

  it "offers choices after the short form" do
    fv_complete(FvChoices, ["__complete", "2", "fvchoices", "-F", "y"]).should eq(["yaml"])
  end

  it "loses to an explicit complete_with:" do
    fv_complete(FvChoicesCw, ["__complete", "2", "fvchoicescw", "--format", ""]).should eq(["custom-only"])
  end
end

describe "flag values: collection flags complete their element type" do
  it "Array(Path) with delimiter: nil emits the files directive" do
    fv_complete(FvColl, ["__complete", "2", "fvcoll", "--input", ""]).should eq([FV_FILES])
    fv_complete(FvColl, ["__complete", "2", "fvcoll", "-i", "/tm"]).should eq([FV_FILES])
  end

  it "Array(Enum) offers member names for the first element" do
    lines = fv_complete(FvColl, ["__complete", "2", "fvcoll", "--unit", ""])
    lines.should contain("bytes")
    lines.should contain("kilobytes")
    lines.should contain("megabytes")
  end

  it "Array(Enum) completes the element after the last delimiter" do
    fv_complete(FvColl, ["__complete", "2", "fvcoll", "--unit", "bytes,m"]).should eq(["bytes,megabytes"])
  end

  it "Array(Enum) offers all members after a trailing delimiter" do
    lines = fv_complete(FvColl, ["__complete", "2", "fvcoll", "-u", "bytes,"])
    lines.should contain("bytes,bytes")
    lines.should contain("bytes,kilobytes")
    lines.should contain("bytes,megabytes")
  end

  it "Set(Enum) completes elements the same way" do
    fv_complete(FvColl, ["__complete", "2", "fvcoll", "--unitset", "bytes,k"]).should eq(["bytes,kilobytes"])
  end

  it "Array(Path) with a delimiter emits the directive only before any delimiter appears" do
    fv_complete(FvColl, ["__complete", "2", "fvcoll", "--joined", ""]).should eq([FV_FILES])
    # A directive can't complete the element after "a," natively; offer nothing
    # rather than a wrong whole-word file completion.
    fv_complete(FvColl, ["__complete", "2", "fvcoll", "--joined", "a,"]).should be_empty
  end
end

describe "flag values: @[Flags] enum members" do
  it "offers member names at an empty value" do
    lines = fv_complete(FvFlagsEnum, ["__complete", "2", "fvflagsenum", "--perms", ""])
    lines.should contain("read")
    lines.should contain("write")
    lines.should contain("execute")
  end

  it "prefix-filters member names" do
    lines = fv_complete(FvFlagsEnum, ["__complete", "2", "fvflagsenum", "-P", "w"])
    lines.should eq(["write"])
  end

  it "keeps offering remaining members after a comma" do
    lines = fv_complete(FvFlagsEnum, ["__complete", "2", "fvflagsenum", "--perms", "read,"])
    lines.should contain("read,write")
    lines.should contain("read,execute")
    lines.should_not contain("read,read")
  end

  it "complete_with: wins over the derived @[Flags] candidates" do
    fv_complete(FvFlagsEnumCw, ["__complete", "2", "fvflagsenumcw", "--perms", ""]).should eq(["custom-perm"])
    fv_complete(FvFlagsEnumCw, ["__complete", "2", "fvflagsenumcw", "--perms", "read,"]).should eq(["custom-perm"])
  end
end

describe "flag values: built-in --shell-completion" do
  it "offers the supported shells" do
    fv_complete(FvPlain, ["__complete", "2", "fvplain", "--shell-completion", ""]).should eq(["bash", "zsh", "fish"])
  end

  it "prefix-filters the shells" do
    fv_complete(FvPlain, ["__complete", "2", "fvplain", "--shell-completion", "b"]).should eq(["bash"])
  end
end

describe "flag values: EnvVar flags complete environment variable names" do
  it "offers matching names from the current environment" do
    ENV["FV_SPEC_PROBE_ONE"] = "1"
    ENV["FV_SPEC_PROBE_TWO"] = "2"
    begin
      lines = fv_complete(FvEnv, ["__complete", "2", "fvenv", "--var", "FV_SPEC_PROBE_"])
      lines.should eq(["FV_SPEC_PROBE_ONE", "FV_SPEC_PROBE_TWO"])
    ensure
      ENV.delete("FV_SPEC_PROBE_ONE")
      ENV.delete("FV_SPEC_PROBE_TWO")
    end
  end
end

describe "positionals: enum-typed slots offer member names" do
  it "completes a scalar enum positional" do
    lines = fv_complete(FvEnumPos, ["__complete", "1", "fvenumpos", ""])
    lines.should contain("bytes")
    lines.should contain("kilobytes")
    lines.should contain("megabytes")
  end

  it "completes a variadic enum positional slot" do
    lines = fv_complete(FvEnumPos, ["__complete", "2", "fvenumpos", "bytes", ""])
    lines.should contain("kilobytes")
  end
end

describe "flag values: -- terminator disables the value branch" do
  it "treats a flag-looking token after -- as a positional" do
    # words: fvmixed -- --count <cursor>; --count here is positional text, so
    # the Path positional's directive must win over --count's (empty) value
    # completion.
    fv_complete(FvMixed, ["__complete", "3", "fvmixed", "--", "--count", ""]).should eq([FV_FILES])
  end
end
