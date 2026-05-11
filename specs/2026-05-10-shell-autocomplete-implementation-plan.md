# Shell::AutoComplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Crystal shard that lets developers define CLIs once via a macro DSL and get parsing, `--help` text, and bash/zsh/fish shell completion (including dynamic completers) for free.

**Architecture:** A macro DSL (`command`, `flag`, `positional`, `positionals`, `subcommand`) annotates classes with internal definitions. Compile-time macros walk those annotations to generate a parser, help text, completion script renderers, and a runtime completion dispatcher. Three parallel hook chains (transformer, validator, completer) extend the type system. The generated shell script inlines static structure for instant completion and falls back to a hidden `__complete` invocation of the binary for dynamic positions.

**Tech Stack:** Crystal 1.20.1+. No runtime dependencies beyond the standard library. Tests via `crystal spec`. Lint via `ameba`. The companion design spec lives at `specs/2026-05-10-shell-autocomplete-api-design.md`.

**Plan organization:** 18 phases, ~50 tasks. Each task is one commit. Phases build on each other; following them in order keeps the test suite green throughout. Phases 1–9 deliver a functional CLI parser without completion; Phases 10–18 layer completion on top.

---

## Working agreements

- **TDD discipline:** every task starts with a failing test. Run `crystal spec` after writing the test (red), then after implementation (green).
- **Commits:** one commit per task. Use Conventional Commits prefixes (`feat:`, `test:`, `refactor:`, `docs:`, etc.).
- **Crystal idioms:** prefer `getter`/`property` over hand-written accessors; macros use `{% %}` (compile-time) and `{{ }}` (interpolation); annotations are read via `ivar.annotation(MyAnn)`.
- **Test fixtures:** test command classes are defined at top-level in the spec file (or in a `spec/fixtures/` module). Macros cannot run inside `it` blocks.
- **Linting:** run `bin/ameba` periodically; address violations as part of the task that introduces them.

---

## File structure

The shard's source tree (built up over the course of the plan):

```
src/
  shell-auto_complete.cr                   # top-level require manifest + VERSION
  shell-auto_complete/
    candidate.cr                            # Candidate struct
    completion_context.cr                   # CompletionContext struct
    command.cr                              # Command base class + dispatch
    annotations.cr                          # CommandDef, FlagDef, PositionalDef, PositionalsDef
    parser.cr                               # ARGV parsing (flag + positional binding)
    help.cr                                 # help-text rendering
    errors.cr                               # ArgumentError subclasses
    macros/
      command.cr                            # `command` and `subcommand` macros
      flag.cr                               # `flag` macro
      positional.cr                         # `positional` and `positionals` macros
      shell_completion_flag.cr              # `shell_completion_flag` macro
      flag_string_parser.cr                 # macro-time helpers for parsing flag-string args
    transformers/
      string.cr
      bool.cr
      numeric.cr                            # Int8..Int64, UInt8..UInt64, Float32, Float64
      char_symbol.cr                        # Char, Symbol
      enum.cr                               # Enum.__arg_transform / __arg_complete
      collection.cr                         # Array(T), Set(T), Hash(String, T)
      stdlib.cr                             # URI, Path, Time, Socket::IPAddress, Log::Severity, Regex
    types/                                  # synthetic types
      positive_int.cr
      non_negative_int.cr
      percentage.cr
      epoch_time.cr
      date.cr
      env_var.cr
    completion/
      dispatcher.cr                         # `__complete` runtime mode + slot detection
      install_flag.cr                       # `--shell-completion` handling
      renderer.cr                           # shared script-generation helpers
      bash.cr
      zsh.cr
      fish.cr
spec/
  spec_helper.cr
  fixtures/                                 # shared test command classes
  ... (mirrors src/ layout for unit specs)
```

---

## Phase 1: Foundations

### Task 1.1: `Candidate` struct

**Files:**
- Create: `src/shell-auto_complete/candidate.cr`
- Create: `spec/shell-auto_complete/candidate_spec.cr`
- Modify: `src/shell-auto_complete.cr`

- [ ] **Step 1: Write failing test**

`spec/shell-auto_complete/candidate_spec.cr`:

```crystal
require "../spec_helper"

describe Shell::AutoComplete::Candidate do
  it "stores a value and optional description" do
    c = Shell::AutoComplete::Candidate.new(value: "foo", description: "the foo")
    c.value.should eq("foo")
    c.description.should eq("the foo")
  end

  it "allows nil description" do
    c = Shell::AutoComplete::Candidate.new(value: "bar")
    c.description.should be_nil
  end
end
```

- [ ] **Step 2: Run and confirm red**

```
crystal spec spec/shell-auto_complete/candidate_spec.cr
```
Expected: compile error — `Candidate` not defined.

- [ ] **Step 3: Implement**

`src/shell-auto_complete/candidate.cr`:

```crystal
module Shell::AutoComplete
  struct Candidate
    getter value : String
    getter description : String?

    def initialize(@value : String, @description : String? = nil)
    end
  end
end
```

- [ ] **Step 4: Wire into top-level require**

`src/shell-auto_complete.cr`:

```crystal
module Shell::AutoComplete
  VERSION = "0.1.0"
end

require "./shell-auto_complete/candidate"
```

- [ ] **Step 5: Run, confirm green, commit**

```
crystal spec spec/shell-auto_complete/candidate_spec.cr
git add src/shell-auto_complete.cr src/shell-auto_complete/candidate.cr spec/shell-auto_complete/candidate_spec.cr
git commit -m "feat: add Candidate struct"
```

### Task 1.2: `CompletionContext` struct

**Files:**
- Create: `src/shell-auto_complete/completion_context.cr`
- Create: `spec/shell-auto_complete/completion_context_spec.cr`
- Modify: `src/shell-auto_complete.cr`

- [ ] **Step 1: Write failing test**

```crystal
require "../spec_helper"

describe Shell::AutoComplete::CompletionContext do
  it "exposes current_word, prior_words, and cword index" do
    ctx = Shell::AutoComplete::CompletionContext.new(
      words: ["mycli", "build", "--flag", "value"],
      cword: 3,
    )
    ctx.current_word.should eq("value")
    ctx.prior_words.should eq(["mycli", "build", "--flag"])
  end

  it "treats cword past the end as empty current_word" do
    ctx = Shell::AutoComplete::CompletionContext.new(
      words: ["mycli", "build"],
      cword: 2,
    )
    ctx.current_word.should eq("")
  end
end
```

- [ ] **Step 2: Run, confirm red.**

- [ ] **Step 3: Implement**

```crystal
module Shell::AutoComplete
  struct CompletionContext
    getter words : Array(String)
    getter cword : Int32

    def initialize(@words : Array(String), @cword : Int32)
    end

    def current_word : String
      cword < words.size ? words[cword] : ""
    end

    def prior_words : Array(String)
      words[0, cword]
    end
  end
end
```

- [ ] **Step 4: Require + run + commit**

Add `require "./shell-auto_complete/completion_context"` to `src/shell-auto_complete.cr`.

```
crystal spec spec/shell-auto_complete/completion_context_spec.cr
git add -A && git commit -m "feat: add CompletionContext struct"
```

### Task 1.3: Internal annotations

**Files:**
- Create: `src/shell-auto_complete/annotations.cr`
- Modify: `src/shell-auto_complete.cr`

No runtime behavior to test; annotations are macro-only metadata. Create them and require the file. Defer testing until they are consumed by `flag`/`command` macros.

- [ ] **Step 1: Implement**

```crystal
module Shell::AutoComplete
  annotation CommandDef
  end

  annotation FlagDef
  end

  annotation PositionalDef
  end

  annotation PositionalsDef
  end
end
```

- [ ] **Step 2: Wire + commit**

```
git add -A && git commit -m "feat: declare internal annotations"
```

### Task 1.4: `Command` base class skeleton

**Files:**
- Create: `src/shell-auto_complete/command.cr`
- Create: `src/shell-auto_complete/errors.cr`
- Modify: `src/shell-auto_complete.cr`
- Create: `spec/shell-auto_complete/command_spec.cr`

- [ ] **Step 1: Write failing test**

```crystal
require "../spec_helper"

class EmptyCommand < Shell::AutoComplete::Command
end

describe Shell::AutoComplete::Command do
  it "is subclassable" do
    EmptyCommand.new.should be_a(Shell::AutoComplete::Command)
  end

  it "raises a NotRunnable when #run is called without override" do
    expect_raises(Shell::AutoComplete::NotRunnable) do
      EmptyCommand.new.run
    end
  end
end
```

- [ ] **Step 2: Run, confirm red.**

- [ ] **Step 3: Implement errors**

`src/shell-auto_complete/errors.cr`:

```crystal
module Shell::AutoComplete
  class Error < Exception; end
  class NotRunnable < Error; end
  class ParseError < Error; end
end
```

- [ ] **Step 4: Implement base class**

`src/shell-auto_complete/command.cr`:

```crystal
module Shell::AutoComplete
  abstract class Command
    def run
      raise NotRunnable.new("#{self.class} must override #run")
    end
  end
end
```

- [ ] **Step 5: Require + run + commit**

`src/shell-auto_complete.cr` should now require, in order: `errors`, `candidate`, `completion_context`, `annotations`, `command`.

```
crystal spec
git add -A && git commit -m "feat: add Command base class"
```

---

## Phase 2: The `command` macro

### Task 2.1: Bare `command` macro

The `command` macro opens a class, makes it a subclass of `Command`, and applies a `CommandDef` annotation.

**Files:**
- Create: `src/shell-auto_complete/macros/command.cr`
- Create: `spec/shell-auto_complete/macros/command_spec.cr`
- Modify: `src/shell-auto_complete.cr`

- [ ] **Step 1: Failing test**

```crystal
require "../../spec_helper"

Shell::AutoComplete.command Foo, name: "foo", description: "the foo command"

describe "command macro" do
  it "creates a Command subclass" do
    Foo.ancestors.should contain(Shell::AutoComplete::Command)
  end

  it "applies a CommandDef annotation with name and description" do
    ann = Foo.annotation(Shell::AutoComplete::CommandDef)
    ann.should_not be_nil
    ann.not_nil![:name].should eq("foo")
    ann.not_nil![:description].should eq("the foo command")
  end
end
```

- [ ] **Step 2: Run, confirm red.**

- [ ] **Step 3: Implement macro**

`src/shell-auto_complete/macros/command.cr`:

```crystal
module Shell::AutoComplete
  macro command(type, **opts, &block)
    @[::Shell::AutoComplete::CommandDef({{**opts}})]
    class {{type.id}} < ::Shell::AutoComplete::Command
      {% if block %}{{ block.body }}{% end %}
    end
  end
end
```

- [ ] **Step 4: Require + run + commit**

Add `require "./shell-auto_complete/macros/command"` to the manifest after `command.cr`.

```
crystal spec
git add -A && git commit -m "feat: command macro creates annotated subclass"
```

### Task 2.2: `command` defaults top-level name from PROGRAM_NAME

**Files:**
- Modify: `src/shell-auto_complete/macros/command.cr`
- Modify: `src/shell-auto_complete/command.cr`
- Add: `spec/shell-auto_complete/macros/command_default_name_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
require "../../spec_helper"

Shell::AutoComplete.command TopLevel, description: "top-level"

describe "top-level command without explicit name" do
  it "defaults the command name to File.basename(PROGRAM_NAME)" do
    TopLevel.command_name.should eq(File.basename(PROGRAM_NAME))
  end
end
```

- [ ] **Step 2: Run, confirm red.**

- [ ] **Step 3: Add `.command_name` to base class**

`src/shell-auto_complete/command.cr`:

```crystal
module Shell::AutoComplete
  abstract class Command
    def self.command_name : String
      ann = self.annotation(::Shell::AutoComplete::CommandDef)
      raise Error.new("#{self} has no CommandDef annotation") unless ann
      name = ann[:name]
      name.is_a?(String) ? name : File.basename(PROGRAM_NAME)
    end

    def run
      raise NotRunnable.new("#{self.class} must override #run")
    end
  end
end
```

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: top-level command defaults to PROGRAM_NAME basename"
```

---

## Phase 3: The `flag` macro — minimum viable

### Task 3.1: Flag-string macro parser

A compile-time helper extracts the canonical long flag, alias list, short flag, and description string from positional macro args. Build it as a standalone macro module so other macros (`flag`, `positional`) can reuse the description extraction.

**Files:**
- Create: `src/shell-auto_complete/macros/flag_string_parser.cr`
- Create: `spec/shell-auto_complete/macros/flag_string_parser_spec.cr`

The parser logic is exercised indirectly through `flag` tests — so this task only defines the parser; the next task tests it through use.

- [ ] **Step 1: Implement helper**

`src/shell-auto_complete/macros/flag_string_parser.cr`:

```crystal
module Shell::AutoComplete::Macros
  # Compile-time helper. Splits an array of literal-string AST nodes
  # into {canonical, aliases, short, description}.
  macro parse_flag_strings(literals)
    {%
      long_forms = [] of StringLiteral
      short = nil
      description = nil
      literals.each do |lit|
        unless lit.is_a?(StringLiteral)
          raise "flag-string args must be string literals; got #{lit.class_name}"
        end
        s = lit.stringify[1..-2] # strip quotes
        if s.starts_with?("--")
          long_forms << lit
        elsif s.starts_with?("-") && s.size == 2
          raise "more than one short flag given" if short
          short = lit
        else
          description ||= lit
        end
      end
      canonical = long_forms.first
      aliases = long_forms[1..-1] || [] of StringLiteral
    %}
    { canonical: {{canonical}}, aliases: {{aliases}}, short: {{short}}, description: {{description || "".stringify}} }
  end
end
```

- [ ] **Step 2: Require + commit**

(No tests yet; tested through `flag`.)

```
git add -A && git commit -m "feat: add flag-string parser macro helper"
```

### Task 3.2: Minimal `flag` macro for `String?` only

Just enough to parse `flag foo : String?, "--foo", "the foo description"` and emit a property + `FlagDef` annotation.

**Files:**
- Create: `src/shell-auto_complete/macros/flag.cr`
- Create: `spec/shell-auto_complete/macros/flag_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
require "../../spec_helper"

Shell::AutoComplete.command Cli1, description: "test" do
  flag message : String?, "--message", "the message"
end

describe "flag macro (basic)" do
  it "generates an instance variable with the declared type" do
    inst = Cli1.new
    inst.message.should be_nil
    inst.message = "hello"
    inst.message.should eq("hello")
  end

  it "attaches a FlagDef annotation with canonical and description" do
    {% begin %}
      ann = Cli1.instance_vars.find { |i| i.name == "message" }
    {% end %}
    # introspection done compile-time; assert via a macro-emitted method
    Cli1.flag_info("message").canonical.should eq("--message")
    Cli1.flag_info("message").description.should eq("the message")
  end
end
```

This test exercises the macro through behavior. The `flag_info` helper is part of the `command` macro's emit (added below).

- [ ] **Step 2: Run, confirm red.**

- [ ] **Step 3: Implement `flag` macro**

`src/shell-auto_complete/macros/flag.cr`:

```crystal
module Shell::AutoComplete
  macro flag(decl, *flag_strings, **opts)
    {%
      # Normalize: allow either a flat list of literal strings OR a single
      # ArrayLiteral of strings.
      strings = if flag_strings.size == 1 && flag_strings[0].is_a?(ArrayLiteral)
                  flag_strings[0]
                else
                  flag_strings
                end
      long_forms = [] of StringLiteral
      short = nil
      description = nil
      strings.each do |lit|
        unless lit.is_a?(StringLiteral)
          raise "flag-string args must be string literals; got #{lit.class_name}"
        end
        raw = lit.stringify[1..-2]
        if raw.starts_with?("--")
          long_forms << lit
        elsif raw.starts_with?("-") && raw.size == 2
          raise "more than one short flag given" if short
          short = lit
        else
          description ||= lit
        end
      end
      raise "no long flag given for #{decl}" if long_forms.empty?
      canonical = long_forms.first
      aliases = long_forms[1..-1] || [] of StringLiteral
      description = description || "".stringify
      consumed_keys = [:shortcut_flags, :validate_with, :transform_with, :complete_with, :negatable, :hidden]
      forwarded = {} of MacroId => ASTNode
      opts.each do |k, v|
        forwarded[k] = v unless consumed_keys.includes?(k)
      end
    %}
    @[::Shell::AutoComplete::FlagDef(
      canonical: {{canonical}},
      aliases: {{aliases}},
      short: {{short}},
      description: {{description}},
      shortcut_flags: {{opts[:shortcut_flags] || false}},
      validate_with: {{opts[:validate_with] || nil}},
      transform_with: {{opts[:transform_with] || nil}},
      complete_with: {{opts[:complete_with] || nil}},
      negatable: {{opts[:negatable].nil? ? true : opts[:negatable]}},
      hidden: {{opts[:hidden] || false}},
      forwarded_opts: {{forwarded}},
    )]
    property {{decl}}
  end
end
```

- [ ] **Step 4: Add `flag_info` helper to base class**

`src/shell-auto_complete/command.cr`:

```crystal
module Shell::AutoComplete
  abstract class Command
    record FlagInfo,
      canonical : String,
      aliases : Array(String),
      short : String?,
      description : String

    macro inherited
      def self.flag_info(ivar_name : String) : ::Shell::AutoComplete::Command::FlagInfo
        {% for ivar in @type.instance_vars %}
          {% if ann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
            if ivar_name == {{ivar.name.stringify}}
              return ::Shell::AutoComplete::Command::FlagInfo.new(
                canonical: {{ann[:canonical]}},
                aliases: {{ann[:aliases]}}.map(&.to_s),
                short: {{ann[:short]}},
                description: {{ann[:description]}},
              )
            end
          {% end %}
        {% end %}
        raise "no flag named #{ivar_name}"
      end
    end

    def self.command_name : String
      ann = self.annotation(::Shell::AutoComplete::CommandDef)
      raise Error.new("#{self} has no CommandDef annotation") unless ann
      name = ann[:name]
      name.is_a?(String) ? name : File.basename(PROGRAM_NAME)
    end

    def run
      raise NotRunnable.new("#{self.class} must override #run")
    end
  end
end
```

- [ ] **Step 5: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: flag macro for nullable String flags"
```

### Task 3.3: Reserved flag names

`--help`, `-h`, and the shell-completion flag may not be declared by user code.

**Files:**
- Modify: `src/shell-auto_complete/macros/flag.cr`
- Add: `spec/shell-auto_complete/macros/flag_reserved_spec.cr`

- [ ] **Step 1: Failing test**

Create a spec that expects compilation failure. Crystal's spec runner can use `Process.run` to invoke a separate compile and assert failure:

```crystal
require "../../spec_helper"

describe "flag macro reserved names" do
  it "rejects declarations of --help" do
    src = <<-CR
      require "./src/shell-auto_complete"
      Shell::AutoComplete.command Bad, description: "x" do
        flag foo : String?, "--help", "x"
      end
    CR
    File.write("/tmp/sac-reserved-help.cr", src)
    result = Process.run("crystal", ["build", "--no-codegen", "/tmp/sac-reserved-help.cr"], output: :pipe, error: :pipe)
    result.success?.should be_false
  end
end
```

- [ ] **Step 2: Run, confirm red.**

- [ ] **Step 3: Implement guard**

Inside the `flag` macro after parsing `long_forms`:

```crystal
{% reserved = ["--help", "-h"] %}
{% long_forms.each do |lf|
     raw = lf.stringify[1..-2]
     raise "#{raw} is a reserved flag name" if reserved.includes?(raw)
   end %}
{% if short
     raw = short.stringify[1..-2]
     raise "#{raw} is a reserved flag name" if reserved.includes?(raw)
   end %}
```

(The shell-completion flag's reservation is handled in Phase 17 where its name becomes configurable.)

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: reserve --help and -h flag names"
```

---

## Phase 4: ARGV parsing — long flags

### Task 4.1: `parse(argv)` for nullable String flags

**Files:**
- Create: `src/shell-auto_complete/parser.cr`
- Modify: `src/shell-auto_complete/command.cr`
- Create: `spec/shell-auto_complete/parser_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
require "../spec_helper"

Shell::AutoComplete.command ParseCli, description: "x" do
  flag message : String?, "--message", "m"
end

describe "ParseCli.parse" do
  it "parses --message value" do
    inst = ParseCli.parse(["--message", "hello"])
    inst.message.should eq("hello")
  end

  it "parses --message=value" do
    inst = ParseCli.parse(["--message=hello"])
    inst.message.should eq("hello")
  end

  it "leaves the flag nil when absent" do
    inst = ParseCli.parse([] of String)
    inst.message.should be_nil
  end

  it "raises ParseError for unknown flags" do
    expect_raises(Shell::AutoComplete::ParseError) do
      ParseCli.parse(["--bogus"])
    end
  end

  it "raises ParseError when a value-taking flag is missing its value" do
    expect_raises(Shell::AutoComplete::ParseError) do
      ParseCli.parse(["--message"])
    end
  end
end
```

- [ ] **Step 2: Run, confirm red.**

- [ ] **Step 3: Implement parser**

`src/shell-auto_complete/parser.cr`:

```crystal
module Shell::AutoComplete
  module Parser
    # FlagSpec is built from each flag's FlagDef annotation at compile time
    # and used at runtime to drive parsing.
    record FlagSpec,
      names : Array(String),
      takes_value : Bool,
      bool_value : Bool? # nil for non-Bool; true/false for --foo/--no-foo

    def self.parse_argv(argv : Array(String), specs : Array(FlagSpec)) : { values: Hash(String, String?), positional: Array(String) }
      values = {} of String => String?
      positional = [] of String
      i = 0
      while i < argv.size
        arg = argv[i]
        if arg == "--"
          positional.concat(argv[(i + 1)..])
          break
        end
        if arg.starts_with?("--")
          name, eq, inline_value = arg.partition('=')
          spec = specs.find { |s| s.names.includes?(name) }
          unless spec
            raise ParseError.new("unknown flag: #{name}")
          end
          if spec.takes_value
            if eq == "="
              values[spec.names[0]] = inline_value
            else
              i += 1
              raise ParseError.new("flag #{name} requires a value") if i >= argv.size
              values[spec.names[0]] = argv[i]
            end
          else
            values[spec.names[0]] = spec.bool_value.to_s
          end
        else
          positional << arg
        end
        i += 1
      end
      { values: values, positional: positional }
    end
  end
end
```

- [ ] **Step 4: Add `.parse` to base class**

In `command.cr`'s `inherited` macro, emit a `parse` class method that builds `specs` from annotations and invokes `Parser.parse_argv`, then assigns values:

```crystal
def self.parse(argv : Array(String)) : self
  specs = [] of ::Shell::AutoComplete::Parser::FlagSpec
  {% for ivar in @type.instance_vars %}
    {% if ann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
      names = [{{ann[:canonical]}}] + {{ann[:aliases]}}
      {% if ann[:short] %} names << {{ann[:short]}} {% end %}
      specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
        names: names,
        takes_value: !({{ivar.type}} == Bool || {{ivar.type}} == Bool?),
        bool_value: nil,
      )
    {% end %}
  {% end %}
  result = ::Shell::AutoComplete::Parser.parse_argv(argv, specs)
  inst = new
  {% for ivar in @type.instance_vars %}
    {% if ann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
      if v = result[:values][{{ann[:canonical]}}]?
        inst.{{ivar.name}} = v.as({{ivar.type}})
      end
    {% end %}
  {% end %}
  inst
end
```

- [ ] **Step 5: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: parse long flags into String? properties"
```

### Task 4.2: Aliases

**Files:**
- Modify: `src/shell-auto_complete/macros/flag.cr` (already collects aliases)
- Create: `spec/shell-auto_complete/parser_aliases_spec.cr`

The parser already includes aliases in `names`; this task verifies parse behavior and asserts canonical-vs-alias storage convention.

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command AliasCli, description: "x" do
  flag message : String?, %w(--message --msg), "m"
end

describe "alias parsing" do
  it "accepts the canonical form" do
    AliasCli.parse(["--message", "hi"]).message.should eq("hi")
  end

  it "accepts an alias" do
    AliasCli.parse(["--msg", "hi"]).message.should eq("hi")
  end
end
```

Verify the existing implementation already covers these. If not, fix and commit.

- [ ] **Step 2: Run, commit**

```
crystal spec
git add -A && git commit -m "test: cover long-flag aliases in parser"
```

### Task 4.3: Short flags + value

**Files:**
- Create: `spec/shell-auto_complete/parser_short_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command ShortCli, description: "x" do
  flag message : String?, "--message", "-m", "m"
end

describe "short flag parsing" do
  it "accepts -m value" do
    ShortCli.parse(["-m", "hi"]).message.should eq("hi")
  end

  it "does not accept -mvalue (no inline short value support)" do
    expect_raises(Shell::AutoComplete::ParseError) do
      ShortCli.parse(["-mhi"])
    end
  end
end
```

- [ ] **Step 2: Implementation** — the parser's `--`-only branch needs to also handle single-`-` short flags. Add a parallel branch:

```crystal
elsif arg.starts_with?("-") && arg.size == 2
  spec = specs.find { |s| s.names.includes?(arg) }
  raise ParseError.new("unknown flag: #{arg}") unless spec
  if spec.takes_value
    i += 1
    raise ParseError.new("flag #{arg} requires a value") if i >= argv.size
    values[spec.names[0]] = argv[i]
  else
    values[spec.names[0]] = spec.bool_value.to_s
  end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: short flag parsing"
```

---

## Phase 5: `dispatch` entry point

### Task 5.1: `dispatch(argv)` parses and calls `#run`

**Files:**
- Modify: `src/shell-auto_complete/command.cr`
- Create: `spec/shell-auto_complete/dispatch_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
class DispatchCli < Shell::AutoComplete::Command
  Shell::AutoComplete.command self, name: "dispatch-cli", description: "x" do
    flag message : String?, "--message", "m"

    @ran = false
    getter? ran

    def run
      @ran = true
    end
  end
end

describe "Command.dispatch" do
  it "parses argv and invokes #run on the populated instance" do
    inst = DispatchCli.dispatch(["--message", "hi"])
    inst.message.should eq("hi")
    inst.ran?.should be_true
  end
end
```

(Note: the `command` macro form `Shell::AutoComplete.command self, ...` is invalid because `self` inside a class body needs special handling. Adjust test to use the top-level form `Shell::AutoComplete.command DispatchCli, ...` instead.)

- [ ] **Step 2: Implement**

In the `inherited` macro body:

```crystal
def self.dispatch(argv : Array(String)) : self
  inst = parse(argv)
  inst.run
  inst
end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: dispatch(argv) parses then invokes #run"
```

---

## Phase 6: Bool flags

### Task 6.1: Bool property + `--foo` / `--no-foo`

**Files:**
- Modify: `src/shell-auto_complete/macros/flag.cr`
- Modify: `src/shell-auto_complete/parser.cr`
- Modify: `src/shell-auto_complete/command.cr` (parse method)
- Create: `spec/shell-auto_complete/bool_flag_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command BoolCli, description: "x" do
  flag color : Bool = true, "--color", "colorize"
end

describe "Bool flag" do
  it "defaults to its declared value" do
    BoolCli.parse([] of String).color.should be_true
  end

  it "accepts --color" do
    BoolCli.parse(["--color"]).color.should be_true
  end

  it "accepts --no-color" do
    BoolCli.parse(["--no-color"]).color.should be_false
  end
end
```

- [ ] **Step 2: Run, confirm red.**

- [ ] **Step 3: Update `flag` macro to emit two FlagSpecs for Bool**

In the parse method's per-flag loop:

```crystal
{% if ivar.type == Bool %}
  specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
    names: [{{ann[:canonical]}}],
    takes_value: false,
    bool_value: true,
  )
  {% if !ann[:negatable].falsey %}
    negative_name = "--no-" + {{ann[:canonical]}}.gsub(/^--/, "")
    specs << ::Shell::AutoComplete::Parser::FlagSpec.new(
      names: [negative_name],
      takes_value: false,
      bool_value: false,
    )
  {% end %}
{% else %}
  ...existing branch...
{% end %}
```

The assignment side, post-parse, sets `inst.color = (value == "true")` for Bool properties.

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: Bool flag with --foo and --no-foo"
```

### Task 6.2: `negatable: false`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command NonNegCli, description: "x" do
  flag verbose : Bool = false, "--verbose", "v", negatable: false
end

describe "negatable: false" do
  it "still accepts --verbose" do
    NonNegCli.parse(["--verbose"]).verbose.should be_true
  end

  it "rejects --no-verbose" do
    expect_raises(Shell::AutoComplete::ParseError) do
      NonNegCli.parse(["--no-verbose"])
    end
  end
end
```

- [ ] **Step 2: Implementation already handles `negatable:` from the FlagDef annotation. Run, commit.**

```
crystal spec
git add -A && git commit -m "feat: negatable: false suppresses --no-foo"
```

---

## Phase 7: Transformer chain

### Task 7.1: Lookup chain at compile time

For a property declared as `flag foo : T`, the macro determines at expansion time which transformer to call. The lookup order:

1. `__arg_transform_foo(value : String)` on the command class
2. `T.__arg_transform(value : String, **opts)` on the declared type
3. `T.parse(value : String)` if defined

If `transform_with: :symbol` is given, that method overrides the chain.

**Files:**
- Modify: `src/shell-auto_complete/macros/flag.cr`
- Modify: `src/shell-auto_complete/command.cr`
- Create: `src/shell-auto_complete/transformers/string.cr`
- Create: `spec/shell-auto_complete/transformer_lookup_spec.cr`

- [ ] **Step 1: Implement String transformer**

`src/shell-auto_complete/transformers/string.cr`:

```crystal
class String
  def self.__arg_transform(value : String, **opts) : String
    value
  end
end
```

(Required for String flags; lookup will find `String.__arg_transform`.)

- [ ] **Step 2: Failing test**

```crystal
Shell::AutoComplete.command IntCli, description: "x" do
  flag count : Int32?, "--count", "c"
end

describe "Int32 transformer" do
  it "parses --count to an Int32" do
    IntCli.parse(["--count", "42"]).count.should eq(42)
  end
end
```

- [ ] **Step 3: Implement numeric transformers**

`src/shell-auto_complete/transformers/numeric.cr`:

```crystal
{% for t in %w(Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64) %}
  struct {{t.id}}
    def self.__arg_transform(value : String, **opts) : {{t.id}}
      value.to_{{t.id.downcase}}
    end
  end
{% end %}

{% for t in %w(Float32 Float64) %}
  struct {{t.id}}
    def self.__arg_transform(value : String, **opts) : {{t.id}}
      value.to_{{t.id.downcase}}
    end
  end
{% end %}
```

- [ ] **Step 4: Update the parse method's assignment side to route through the transformer**

In the `inherited` macro:

```crystal
{% inner = ivar.type.union? ? ivar.type.union_types.find { |u| u != Nil } : ivar.type %}
if v = result[:values][{{ann[:canonical]}}]?
  inst.{{ivar.name}} = {{inner}}.__arg_transform(v, **{{ann[:forwarded_opts]}})
end
```

(Union with `Nil` is the nullable case; pick the non-nil branch as the transformer's host type.)

- [ ] **Step 5: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: transformer chain for String and numeric scalars"
```

### Task 7.2: `transform_with:` override

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command CustomCli, description: "x" do
  flag count : Int32?, "--count", "c", transform_with: :my_int

  def self.my_int(value : String) : Int32
    value.to_i * 10
  end
end

describe "transform_with" do
  it "uses the named class method" do
    CustomCli.parse(["--count", "3"]).count.should eq(30)
  end
end
```

- [ ] **Step 2: Implementation** — in the assignment-side macro:

```crystal
{% tx = ann[:transform_with] %}
{% if tx %}
  inst.{{ivar.name}} = self.{{tx.id}}(v)
{% else %}
  inst.{{ivar.name}} = {{inner}}.__arg_transform(v, **{{ann[:forwarded_opts]}})
{% end %}
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: transform_with: override"
```

### Task 7.3: Union types require `transform_with:`

- [ ] **Step 1: Failing test** that asserts compile error when a non-nullable union (`String | Int32`) has no `transform_with:`.

(Use the `Process.run "crystal build --no-codegen ..."` pattern from Task 3.3.)

- [ ] **Step 2: Implementation** — in the `flag` macro:

```crystal
{%
  inner_type = decl.type
  is_nillable = inner_type.is_a?(Union) && inner_type.types.includes?(Nil)
  non_nil_types = is_nillable ? inner_type.types.reject { |t| t == Nil } : (inner_type.is_a?(Union) ? inner_type.types : [inner_type])
  if non_nil_types.size > 1 && opts[:transform_with] == nil
    raise "Union types require an explicit transform_with: on flag #{decl}"
  end
%}
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: union types must declare transform_with:"
```

---

## Phase 8: Validator chain

### Task 8.1: Validator lookup + `range:` on numerics

**Files:**
- Modify: `src/shell-auto_complete/transformers/numeric.cr`
- Modify: `src/shell-auto_complete/command.cr` (post-transform validation step)
- Create: `spec/shell-auto_complete/validator_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command PortCli, description: "x" do
  flag port : Int32?, "--port", "p", range: 1..65535
end

describe "range: validator" do
  it "accepts an in-range value" do
    PortCli.parse(["--port", "8080"]).port.should eq(8080)
  end

  it "rejects out-of-range" do
    expect_raises(Shell::AutoComplete::ParseError, /out of range/) do
      PortCli.parse(["--port", "70000"])
    end
  end
end
```

- [ ] **Step 2: Implement numeric validators**

In `numeric.cr`, add for each numeric type:

```crystal
def self.__arg_validate(value : self, **opts) : Bool | String
  if (range = opts[:range]?) && !range.includes?(value)
    return "#{value} is out of range #{range}"
  end
  true
end
```

- [ ] **Step 3: Emit validation in the parse method**

After assignment:

```crystal
{% vw = ann[:validate_with] %}
{% if vw %}
  result_v = self.{{vw.id}}(inst.{{ivar.name}}, **{{ann[:forwarded_opts]}})
{% else %}
  result_v = {{inner}}.responds_to?(:__arg_validate) ?
    {{inner}}.__arg_validate(inst.{{ivar.name}}, **{{ann[:forwarded_opts]}}) :
    true
{% end %}
case result_v
when true then nil
when String then raise ParseError.new(result_v.as(String))
when false then raise ParseError.new("not a valid {{ivar.name}}")
end
```

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: validator chain + range: for numerics"
```

### Task 8.2: `matches:` and `choices:` for String

- [ ] **Step 1: Failing tests**

```crystal
Shell::AutoComplete.command MatchCli, description: "x" do
  flag name : String?, "--name", "n", matches: /\A[a-z][a-z0-9-]*\z/
end

Shell::AutoComplete.command ChoicesCli, description: "x" do
  flag color : String?, "--color", "c", choices: %w[red green blue]
end

describe "matches:" do
  it "accepts a matching value" do
    MatchCli.parse(["--name", "abc-123"]).name.should eq("abc-123")
  end

  it "rejects a non-matching value" do
    expect_raises(Shell::AutoComplete::ParseError) do
      MatchCli.parse(["--name", "Abc"])
    end
  end
end

describe "choices:" do
  it "accepts a listed value" do
    ChoicesCli.parse(["--color", "red"]).color.should eq("red")
  end

  it "rejects unlisted values" do
    expect_raises(Shell::AutoComplete::ParseError) do
      ChoicesCli.parse(["--color", "purple"])
    end
  end
end
```

- [ ] **Step 2: Implement in `transformers/string.cr`**

```crystal
class String
  def self.__arg_transform(value : String, **opts) : String
    value
  end

  def self.__arg_validate(value : String, **opts) : Bool | String
    if (re = opts[:matches]?) && !re.matches?(value)
      return "#{value} does not match #{re}"
    end
    if (cs = opts[:choices]?) && !cs.includes?(value)
      return "#{value} is not one of #{cs.join(", ")}"
    end
    true
  end
end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: matches: and choices: validation for String"
```

### Task 8.3: `validate_with:` override

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command VWCli, description: "x" do
  flag count : Int32 = 1, "--count", "c", validate_with: :check_count

  def self.check_count(value : Int32) : String?
    value.even? ? "#{value} must be odd" : nil
  end
end

describe "validate_with" do
  it "accepts a valid value" do
    VWCli.parse(["--count", "3"]).count.should eq(3)
  end

  it "rejects an invalid value" do
    expect_raises(Shell::AutoComplete::ParseError, /must be odd/) do
      VWCli.parse(["--count", "2"])
    end
  end
end
```

(The validator return shape is `Bool | String`. `String?` from the example needs converting — or expand the contract to accept `Nil` as "accept." Decide: the spec says `Bool | String`, so `nil` is not a valid return. Adjust the test to return `true` / a String.)

Adjusted test:

```crystal
def self.check_count(value : Int32) : Bool | String
  value.odd? || "#{value} must be odd"
end
```

- [ ] **Step 2: Wiring is already handled in 8.1's macro. Run, commit.**

```
crystal spec
git add -A && git commit -m "feat: validate_with: override"
```

---

## Phase 9: Help text

### Task 9.1: Default help generation

**Files:**
- Create: `src/shell-auto_complete/help.cr`
- Modify: `src/shell-auto_complete/command.cr` (intercept `--help` in `dispatch`)
- Create: `spec/shell-auto_complete/help_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command HelpCli, name: "helpcli", description: "demo command" do
  flag message : String?, "--message", "-m", "the message"
  flag count : Int32 = 1, "--count", "iterations"
end

describe "Command.help" do
  it "renders usage, description, and options" do
    text = HelpCli.help
    text.should contain("Usage: helpcli")
    text.should contain("demo command")
    text.should contain("--message")
    text.should contain("the message")
    text.should contain("--count")
  end
end
```

- [ ] **Step 2: Implement `help.cr`**

```crystal
module Shell::AutoComplete::Help
  def self.render(command_name : String, description : String,
                  flags : Array(Tuple(String, Array(String), String?, String, Bool)),
                  positionals : Array(Tuple(String, String, Bool)),
                  subcommands : Array(Tuple(String, String)),
                  header : String? = nil, footer : String? = nil, usage : String? = nil) : String
    io = String.build do |s|
      s << header << "\n\n" if header
      s << "Usage: " << (usage || default_usage(command_name, flags, positionals, subcommands)) << "\n\n"
      s << description << "\n"
      unless subcommands.empty?
        s << "\nSubcommands:\n"
        subcommands.each { |name, desc| s << "  " << name.ljust(20) << "  " << desc << "\n" }
      end
      visible_flags = flags.reject { |_, _, _, _, hidden| hidden }
      unless visible_flags.empty?
        s << "\nOptions:\n"
        visible_flags.each do |canonical, aliases, short, desc, _|
          forms = [canonical].concat(aliases)
          forms << short if short
          s << "  " << forms.join(", ").ljust(30) << "  " << desc << "\n"
        end
      end
      visible_pos = positionals.reject { |_, _, hidden| hidden }
      unless visible_pos.empty?
        s << "\nPositional arguments:\n"
        visible_pos.each { |name, desc, _| s << "  " << name.ljust(20) << "  " << desc << "\n" }
      end
      s << "\n" << footer << "\n" if footer
    end
    io
  end

  private def self.default_usage(name, flags, positionals, subcommands) : String
    parts = [name]
    parts << "[options]" unless flags.empty?
    parts << "<command>" unless subcommands.empty?
    parts.join(" ")
  end
end
```

- [ ] **Step 3: Emit `help` method via inherited macro**

In `Command.inherited`:

```crystal
def self.help : String
  flags = [] of Tuple(String, Array(String), String?, String, Bool)
  {% for ivar in @type.instance_vars %}
    {% if ann = ivar.annotation(::Shell::AutoComplete::FlagDef) %}
      flags << { {{ann[:canonical]}}, {{ann[:aliases]}}, {{ann[:short]}}, {{ann[:description]}}, {{ann[:hidden]}} }
    {% end %}
  {% end %}
  positionals = [] of Tuple(String, String, Bool)
  subcommands = [] of Tuple(String, String)
  cmd_ann = self.annotation(::Shell::AutoComplete::CommandDef)
  ::Shell::AutoComplete::Help.render(
    command_name,
    cmd_ann.not_nil![:description].to_s,
    flags,
    positionals,
    subcommands,
    header: cmd_ann.not_nil![:header]?.as(String?),
    footer: cmd_ann.not_nil![:footer]?.as(String?),
    usage: cmd_ann.not_nil![:usage]?.as(String?),
  )
end
```

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: auto-generated help text"
```

### Task 9.2: `--help` / `-h` intercept in dispatch

- [ ] **Step 1: Failing test**

```crystal
describe "dispatch --help" do
  it "prints help and does not call #run" do
    io = IO::Memory.new
    HelpCli.dispatch(["--help"], stdout: io)
    io.to_s.should contain("Usage: helpcli")
  end
end
```

- [ ] **Step 2: Update `dispatch` signature**

```crystal
def self.dispatch(argv : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : self?
  if argv.includes?("--help") || argv.includes?("-h")
    stdout.puts help
    return nil
  end
  inst = parse(argv)
  inst.run
  inst
end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: --help and -h intercept in dispatch"
```

### Task 9.3: `hidden: true` omission

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command HiddenCli, name: "h", description: "x" do
  flag debug : Bool = false, "--debug", "developer-only", hidden: true
end

describe "hidden flag" do
  it "is parsed normally" do
    HiddenCli.parse(["--debug"]).debug.should be_true
  end

  it "is omitted from help" do
    HiddenCli.help.should_not contain("--debug")
  end
end
```

- [ ] **Step 2: Help generator already filters by `hidden`. Verify and commit.**

```
crystal spec
git add -A && git commit -m "feat: hidden: true omits flags from help"
```

---

## Phase 10: Positional arguments (scalar)

### Task 10.1: `positional` macro + scalar binding

**Files:**
- Create: `src/shell-auto_complete/macros/positional.cr`
- Modify: `src/shell-auto_complete/command.cr` (parse extends to bind positionals)
- Create: `spec/shell-auto_complete/positional_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command PosCli, name: "pos", description: "x" do
  positional name : String, "the name"
end

describe "positional macro" do
  it "binds the first positional to the property" do
    PosCli.parse(["alice"]).name.should eq("alice")
  end

  it "errors when the required positional is missing" do
    expect_raises(Shell::AutoComplete::ParseError) do
      PosCli.parse([] of String)
    end
  end
end
```

- [ ] **Step 2: Implement positional macro**

`src/shell-auto_complete/macros/positional.cr`:

```crystal
module Shell::AutoComplete
  macro positional(decl, *strings, **opts)
    {%
      description = nil
      strings.each do |lit|
        raise "positional args must be string literals" unless lit.is_a?(StringLiteral)
        description ||= lit
      end
      raise "positional requires a description" unless description
      consumed = [:complete_with, :hidden]
      forwarded = {} of MacroId => ASTNode
      opts.each do |k, v|
        forwarded[k] = v unless consumed.includes?(k)
      end
    %}
    @[::Shell::AutoComplete::PositionalDef(
      description: {{description}},
      complete_with: {{opts[:complete_with] || nil}},
      hidden: {{opts[:hidden] || false}},
      forwarded_opts: {{forwarded}},
    )]
    property {{decl}}
  end
end
```

- [ ] **Step 3: Update parse method to bind positionals**

Inside `inherited`'s `parse`:

```crystal
positional_tokens = result[:positional]
pos_index = 0
{% for ivar in @type.instance_vars %}
  {% if ann = ivar.annotation(::Shell::AutoComplete::PositionalDef) %}
    raise ParseError.new("missing positional argument: {{ivar.name}}") if pos_index >= positional_tokens.size && !({{ivar.type}}.nilable?)
    if pos_index < positional_tokens.size
      raw = positional_tokens[pos_index]
      {% inner = ivar.type.union? ? ivar.type.union_types.find { |u| u != Nil } : ivar.type %}
      inst.{{ivar.name}} = {{inner}}.__arg_transform(raw, **{{ann[:forwarded_opts]}})
      pos_index += 1
    end
  {% end %}
{% end %}
raise ParseError.new("too many positional arguments") if pos_index < positional_tokens.size && !has_variadic?
```

(`has_variadic?` is a compile-time-determined helper; for now, hard-code `false` and revisit in Phase 11.)

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: positional macro for scalar args"
```

### Task 10.2: Multiple positionals + optional trailing + `--` separator

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command MultiPosCli, name: "m", description: "x" do
  positional first : String, "first"
  positional second : String?, "second optional"
end

describe "multiple + optional trailing positionals" do
  it "binds both when given" do
    inst = MultiPosCli.parse(["a", "b"])
    inst.first.should eq("a")
    inst.second.should eq("b")
  end

  it "leaves the optional positional nil when missing" do
    inst = MultiPosCli.parse(["a"])
    inst.first.should eq("a")
    inst.second.should be_nil
  end
end

Shell::AutoComplete.command DashCli, name: "d", description: "x" do
  flag message : String?, "--message", "m"
  positional rest : String, "rest"
end

describe "-- separator" do
  it "treats -- as the end of flag parsing" do
    inst = DashCli.parse(["--message", "hi", "--", "--not-a-flag"])
    inst.message.should eq("hi")
    inst.rest.should eq("--not-a-flag")
  end
end
```

- [ ] **Step 2: Verify the parser's existing `--` handling. Iterate on the binding logic if needed.**

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: multiple positionals + optional trailing + -- handling"
```

---

## Phase 11: Variadic positionals (`positionals`)

### Task 11.1: `positionals` macro

**Files:**
- Modify: `src/shell-auto_complete/macros/positional.cr`
- Create: `spec/shell-auto_complete/positionals_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command VarCli1, name: "v", description: "x" do
  positional  name  : String,      "n"
  positionals files : Array(Path), "files", min: 1
end

describe "positionals (trailing variadic)" do
  it "binds leading scalar + variadic" do
    inst = VarCli1.parse(["alpha", "a.txt", "b.txt"])
    inst.name.should eq("alpha")
    inst.files.size.should eq(2)
  end

  it "enforces min" do
    expect_raises(Shell::AutoComplete::ParseError) do
      VarCli1.parse(["alpha"])
    end
  end
end
```

- [ ] **Step 2: Add macro**

```crystal
module Shell::AutoComplete
  macro positionals(decl, *strings, **opts)
    {%
      # Validate that decl.type is a collection
      ct = decl.type
      collection = ["Array", "Set", "Hash"].any? { |c| ct.stringify.starts_with?(c + "(") }
      raise "positionals must be Array(T), Set(T), or Hash(String, T)" unless collection
      description = nil
      strings.each do |lit|
        raise "positionals args must be string literals" unless lit.is_a?(StringLiteral)
        description ||= lit
      end
      raise "positionals requires a description" unless description
      consumed = [:min, :max, :complete_with, :hidden]
      forwarded = {} of MacroId => ASTNode
      opts.each do |k, v|
        forwarded[k] = v unless consumed.includes?(k)
      end
    %}
    @[::Shell::AutoComplete::PositionalsDef(
      description: {{description}},
      min: {{opts[:min] || 0}},
      max: {{opts[:max] || Int32::MAX}},
      complete_with: {{opts[:complete_with] || nil}},
      hidden: {{opts[:hidden] || false}},
      forwarded_opts: {{forwarded}},
    )]
    property {{decl}} = {{decl.type}}.new
  end
end
```

- [ ] **Step 3: Update positional binding in parse**

Replace the simple positional-binding section with the shift-from-stack pattern from the spec:

```crystal
stack = result[:positional].dup
# Count trailing scalars
trailing_count = 0
has_variadic = false
{% for ivar in @type.instance_vars.reverse %}
  {% if ivar.annotation(::Shell::AutoComplete::PositionalDef) %}
    trailing_count += 1 unless has_variadic
  {% elsif ivar.annotation(::Shell::AutoComplete::PositionalsDef) %}
    has_variadic = true
  {% end %}
{% end %}
# (then) shift leading, loop variadic, shift trailing — see spec for sketch
```

The full implementation is mechanical: iterate ivars front-to-back, branching on which annotation each has.

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: positionals (variadic) with leading/trailing binding"
```

### Task 11.2: Leading + variadic + trailing case

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command StageCli, name: "stage", description: "x" do
  positional  name        : String,     "n"
  positionals files       : Array(Path), "f"
  positional  destination : Path,        "d"
end

describe "name + variadic + destination" do
  it "binds with empty variadic" do
    inst = StageCli.parse(["a", "dest"])
    inst.name.should eq("a")
    inst.files.empty?.should be_true
    inst.destination.to_s.should eq("dest")
  end

  it "binds with populated variadic" do
    inst = StageCli.parse(["a", "x", "y", "dest"])
    inst.name.should eq("a")
    inst.files.map(&.to_s).should eq(%w[x y])
    inst.destination.to_s.should eq("dest")
  end

  it "errors when too few tokens" do
    expect_raises(Shell::AutoComplete::ParseError) do
      StageCli.parse(["a"])
    end
  end
end
```

- [ ] **Step 2: Add Path transformer (just enough for this test)**

`src/shell-auto_complete/transformers/stdlib.cr` (partial):

```crystal
struct Path
  def self.__arg_transform(value : String, **opts) : Path
    Path.new(value)
  end
end
```

- [ ] **Step 3: Implement Array(T) transformer (just enough)**

`src/shell-auto_complete/transformers/collection.cr`:

```crystal
class Array(T)
  def self.__arg_transform(value : String, **opts) : Array(T)
    delim = opts[:delimiter]? || ","
    parts = delim.nil? ? [value] : value.split(delim)
    parts.map { |p| T.__arg_transform(p, **opts).as(T) }
  end
end
```

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: leading + variadic + trailing positional binding"
```

### Task 11.3: Compile-time error on multiple `positionals`

- [ ] **Step 1: Failing test** (compile-failure assertion using `Process.run "crystal build --no-codegen"`).

- [ ] **Step 2: Implementation** — add a `@type.instance_vars` scan in `command`'s emitted `inherited` macro that raises at compile time when more than one `PositionalsDef` is present.

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: compile error on multiple positionals declarations"
```

---

## Phase 12: Subcommands

### Task 12.1: `subcommand` macro + routing

**Files:**
- Modify: `src/shell-auto_complete/macros/command.cr`
- Create: `spec/shell-auto_complete/subcommand_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command SubChild, name: "child", description: "child" do
  flag value : String?, "--value", "v"

  def run
    @ran_child = true
  end

  getter? ran_child : Bool = false
end

Shell::AutoComplete.command SubParent, name: "parent", description: "parent" do
  subcommand SubChild
end

describe "subcommand" do
  it "routes 'parent child --value x' into SubChild" do
    inst = SubParent.dispatch(["child", "--value", "x"])
    inst.should be_a(SubChild)
    inst.as(SubChild).value.should eq("x")
    inst.as(SubChild).ran_child?.should be_true
  end
end
```

- [ ] **Step 2: Implement `subcommand` macro**

```crystal
macro subcommand(klass)
  SUBCOMMANDS << { {{klass.id.stringify}}, {{klass}} }
end
```

`SUBCOMMANDS` is a constant array initialized once by the `command` macro:

```crystal
macro command(type, **opts, &block)
  @[::Shell::AutoComplete::CommandDef({{**opts}})]
  class {{type.id}} < ::Shell::AutoComplete::Command
    SUBCOMMANDS = [] of Tuple(String, ::Shell::AutoComplete::Command.class)
    {% if block %}{{block.body}}{% end %}
  end
end
```

`dispatch` checks whether the first ARGV token matches a subcommand name; if so, routes to that subclass's `dispatch` with the remainder.

- [ ] **Step 3: Update dispatch**

```crystal
def self.dispatch(argv, stdout = STDOUT, stderr = STDERR)
  return print_help(stdout) if argv.includes?("--help") || argv.includes?("-h")
  unless argv.empty?
    SUBCOMMANDS.each do |name, klass|
      return klass.dispatch(argv[1..], stdout: stdout, stderr: stderr) if argv[0] == name
    end
  end
  inst = parse(argv)
  inst.run
  inst
end
```

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: subcommand routing"
```

### Task 12.2: Sub-subcommands + no-positionals constraint

- [ ] **Step 1: Failing test** for a 3-deep tree (root → mid → leaf).

- [ ] **Step 2: Failing test** that a `command` with both `subcommand` and `positional`/`positionals` fails at compile time.

- [ ] **Step 3: Implement compile-time guard in `command`'s `inherited`:**

```crystal
{% has_sub = false; has_pos = false %}
{% for ivar in @type.instance_vars %}
  {% has_pos = true if ivar.annotation(::Shell::AutoComplete::PositionalDef) || ivar.annotation(::Shell::AutoComplete::PositionalsDef) %}
{% end %}
{% if SUBCOMMANDS.size > 0 && has_pos %}
  {% raise "command #{@type} declares both subcommands and positionals" %}
{% end %}
```

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: sub-subcommands + no-positionals-with-subcommands guard"
```

### Task 12.3: Help integration for subcommands

- [ ] **Step 1: Failing test**: help text for `SubParent` lists `child` as a subcommand.

- [ ] **Step 2: Implement** — in the `help` emit, populate `subcommands` from `SUBCOMMANDS`.

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: subcommand listing in help"
```

---

## Phase 13: Enums

### Task 13.1: Ordinary enum transformer + completer

**Files:**
- Create: `src/shell-auto_complete/transformers/enum.cr`
- Create: `spec/shell-auto_complete/enum_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
enum EnumLogLevel
  Debug
  Info
  Warn
  Error
end

Shell::AutoComplete.command EnumCli, name: "e", description: "x" do
  flag level : EnumLogLevel = EnumLogLevel::Info, "--level", "lvl"
end

describe "ordinary enum flag" do
  it "parses case names case-insensitively and kebab-cased" do
    EnumCli.parse(["--level", "debug"]).level.should eq(EnumLogLevel::Debug)
    EnumCli.parse(["--level", "WARN"]).level.should eq(EnumLogLevel::Warn)
  end

  it "rejects unknown cases" do
    expect_raises(Shell::AutoComplete::ParseError) do
      EnumCli.parse(["--level", "trace"])
    end
  end
end
```

- [ ] **Step 2: Implement**

```crystal
struct Enum
  def self.__arg_transform(value : String, **opts)
    parse(value.gsub("-", "_"))
  end

  def self.__arg_complete(prefix : String, **opts) : Array(String)
    names.map { |n| n.to_s.underscore.gsub("_", "-") }
  end
end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: enum transformer + case-name completer"
```

### Task 13.2: `shortcut_flags: true`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command SCFCli, name: "s", description: "x" do
  flag level : EnumLogLevel = EnumLogLevel::Info, "--level", "l", shortcut_flags: true
end

describe "shortcut_flags" do
  it "still parses the canonical form" do
    SCFCli.parse(["--level", "debug"]).level.should eq(EnumLogLevel::Debug)
  end

  it "generates --debug, --info, --warn, --error" do
    SCFCli.parse(["--debug"]).level.should eq(EnumLogLevel::Debug)
    SCFCli.parse(["--warn"]).level.should eq(EnumLogLevel::Warn)
  end

  it "applies last-one-wins on conflict" do
    SCFCli.parse(["--debug", "--error"]).level.should eq(EnumLogLevel::Error)
  end
end
```

- [ ] **Step 2: Implement** — in the `flag` macro's emit, when `shortcut_flags: true` and the property type is an enum (not `@[Flags]`), emit one extra `FlagSpec` per case that sets the property to that case.

- [ ] **Step 3: Compile-time error when used on a `@[Flags]` enum.**

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: shortcut_flags generates per-case shortcut flags"
```

### Task 13.3: `@[Flags]` enum comma-separated parsing

- [ ] **Step 1: Failing test**

```crystal
@[Flags]
enum Perm
  Read
  Write
  Execute
end

Shell::AutoComplete.command FlagsCli, name: "f", description: "x" do
  flag perms : Perm = Perm::None, "--perms", "p"
end

describe "@[Flags] enum" do
  it "parses comma-separated list" do
    inst = FlagsCli.parse(["--perms", "read,write"])
    inst.perms.read?.should be_true
    inst.perms.write?.should be_true
    inst.perms.execute?.should be_false
  end
end
```

- [ ] **Step 2: Update Enum transformer** to use `parse(value)` which already handles comma-separated for `@[Flags]` enums (verify with stdlib docs).

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: @[Flags] enum comma-separated parsing"
```

---

## Phase 14: Collections (full)

### Task 14.1: `Array(T)` delimiter + accumulation

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command ArrCli, name: "a", description: "x" do
  flag tags : Array(String) = [] of String, "--tag", "t"
end

describe "Array(T) flag" do
  it "accumulates over multiple occurrences" do
    ArrCli.parse(["--tag", "a", "--tag", "b"]).tags.should eq(%w[a b])
  end

  it "splits a single occurrence on the default delimiter" do
    ArrCli.parse(["--tag", "a,b,c"]).tags.should eq(%w[a b c])
  end
end

Shell::AutoComplete.command ArrSemCli, name: "as", description: "x" do
  flag tags : Array(String) = [] of String, "--tag", "t", delimiter: ";"
end

it "respects custom delimiter" do
  ArrSemCli.parse(["--tag", "a;b"]).tags.should eq(%w[a b])
end

Shell::AutoComplete.command ArrNoSplitCli, name: "ans", description: "x" do
  flag tags : Array(String) = [] of String, "--tag", "t", delimiter: nil
end

it "treats nil delimiter as no splitting" do
  ArrNoSplitCli.parse(["--tag", "a,b"]).tags.should eq(["a,b"])
end
```

- [ ] **Step 2: Update parse method** to detect repeated flags and accumulate into `Array(T)` properties. The accumulation lives in the parser (it must record multiple values per flag), while the transformer handles per-occurrence splitting.

Replace `values: Hash(String, String?)` with `values: Hash(String, Array(String))`.

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: Array(T) accumulation + delimiter:"
```

### Task 14.2: `Set(T)` + `set_operations:`

- [ ] **Step 1: Failing tests** for both default-Set behavior (no sigils) and `set_operations: true`.

- [ ] **Step 2: Implement Set transformer** in `collection.cr`:

```crystal
class Set(T)
  def self.__arg_transform(value : String, **opts) : Set(T)
    delim = opts[:delimiter]? || ","
    ops = opts[:set_operations]? == true
    parts = delim.nil? ? [value] : value.split(delim)
    result = Set(T).new
    parts.each do |raw|
      raw = raw.strip
      if ops && raw.starts_with?("-")
        result.delete(T.__arg_transform(raw[1..], **opts))
      elsif ops && raw.starts_with?("+")
        result.add(T.__arg_transform(raw[1..], **opts))
      else
        result.add(T.__arg_transform(raw, **opts))
      end
    end
    result
  end
end
```

(For accumulation across multiple occurrences, the parser combines per-occurrence Set results with union (or difference for `-` prefixes).)

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: Set(T) + set_operations: prefixes"
```

### Task 14.3: `Hash(String, T)`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command HashCli, name: "h", description: "x" do
  flag env : Hash(String, String) = {} of String => String, "--env", "e"
end

describe "Hash(String, T)" do
  it "parses key=value" do
    inst = HashCli.parse(["--env", "FOO=bar", "--env", "BAZ=qux"])
    inst.env.should eq({"FOO" => "bar", "BAZ" => "qux"})
  end

  it "deletes with -key" do
    inst = HashCli.parse(["--env", "FOO=bar", "--env", "-FOO"])
    inst.env.empty?.should be_true
  end
end
```

- [ ] **Step 2: Implement**

```crystal
class Hash(K, V)
  def self.__arg_transform(value : String, **opts) : Hash(String, V) forall V
    {% raise "Hash key must be String for CLI parsing" if K != String %}
    delim = opts[:delimiter]? || nil
    occurrences = delim ? value.split(delim) : [value]
    result = {} of String => V
    occurrences.each do |occ|
      if m = occ.match(/\A(?<key>[A-Za-z0-9_+]+)=(?<value>.*)\z/)
        result[m["key"]] = V.__arg_transform(m["value"], **opts).as(V)
      elsif m = occ.match(/\A-(?<key>[A-Za-z0-9_-]+)\z/)
        result.delete(m["key"])
      else
        raise ParseError.new("invalid hash entry: #{occ}")
      end
    end
    result
  end
end
```

Accumulation across occurrences in the parser merges hashes (later occurrences overwrite, `-key` deletes).

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: Hash(String, T) key=value parsing"
```

---

## Phase 15: Stdlib type transformers

### Task 15.1: URI, Time, Socket::IPAddress, Log::Severity, Regex, File, Dir

**Files:**
- Modify: `src/shell-auto_complete/transformers/stdlib.cr`
- Create: `spec/shell-auto_complete/stdlib_transformers_spec.cr`

- [ ] **Step 1: Write tests for each type** (one `it` per type; round-trip a representative value).

- [ ] **Step 2: Implement**

```crystal
require "uri"
require "socket"
require "log"

struct URI
  def self.__arg_transform(value : String, **opts) : URI
    URI.parse(value)
  end
end

struct Time
  def self.__arg_transform(value : String, **opts) : Time
    # Try ISO 8601, RFC 3339, RFC 2822, then a few common formats
    [Time::Format::ISO_8601_DATE_TIME, Time::Format::RFC_3339, Time::Format::RFC_2822].each do |fmt|
      begin
        return fmt.parse(value, location: Time::Location.local)
      rescue
        next
      end
    end
    raise ParseError.new("unrecognized time format: #{value}")
  end
end

struct Socket::IPAddress
  def self.__arg_transform(value : String, **opts) : Socket::IPAddress
    host, _, port = value.rpartition(":")
    Socket::IPAddress.new(host.empty? ? value : host, host.empty? ? 0 : port.to_i)
  end
end

enum ::Log::Severity
  def self.__arg_transform(value : String, **opts) : ::Log::Severity
    parse(value.gsub("-", "_"))
  end
end

struct Regex
  def self.__arg_transform(value : String, **opts) : Regex
    Regex.new(value)
  end
end

# Path is already in Phase 11. Add File and Dir here:
struct Path
  # already implemented
end

# File and Dir are *not* their own types in Crystal — both result in Path.
# Synthesize via dedicated modules under Types/.
```

(`File` and `Dir` are handled as synthetic types — see Phase 16.)

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: stdlib type transformers"
```

---

## Phase 16: Synthetic types

### Task 16.1: PositiveInt, NonNegativeInt, Percentage

**Files:**
- Create: `src/shell-auto_complete/types/positive_int.cr`
- Create: `src/shell-auto_complete/types/non_negative_int.cr`
- Create: `src/shell-auto_complete/types/percentage.cr`
- Create: `spec/shell-auto_complete/types/synthetic_int_spec.cr`

- [ ] **Step 1: Failing tests** for each (round-trip plus a rejection).

- [ ] **Step 2: Implement (template — `PositiveInt`)**

```crystal
module Shell::AutoComplete::Types::PositiveInt
  def self.__arg_transform(value : String, **opts) : Int32
    value.to_i
  end

  def self.__arg_validate(value : Int32, **opts) : Bool | String
    value > 0 || "#{value} must be positive"
  end
end
```

NonNegativeInt and Percentage are analogous.

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: PositiveInt, NonNegativeInt, Percentage synthetic types"
```

### Task 16.2: EpochTime, Date

- [ ] **Step 1: Failing tests**

- [ ] **Step 2: Implement**

```crystal
module Shell::AutoComplete::Types::EpochTime
  def self.__arg_transform(value : String, **opts) : Time
    Time.unix(value.to_f.to_i)
  end
end

module Shell::AutoComplete::Types::Date
  def self.__arg_transform(value : String, **opts) : Time
    Time.parse_iso8601(value)
  end
end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: EpochTime and Date synthetic types"
```

### Task 16.3: EnvVar

- [ ] **Step 1: Failing tests**

```crystal
Shell::AutoComplete.command EnvCli, name: "e", description: "x" do
  flag var : Shell::AutoComplete::Types::EnvVar?, "--var", "v"
end

describe "EnvVar type" do
  it "accepts valid names" do
    EnvCli.parse(["--var", "PATH"]).var.should eq("PATH")
  end

  it "rejects names with hyphens" do
    expect_raises(Shell::AutoComplete::ParseError) do
      EnvCli.parse(["--var", "PA-TH"])
    end
  end
end
```

- [ ] **Step 2: Implement**

```crystal
module Shell::AutoComplete::Types::EnvVar
  NAME_RE = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  def self.__arg_transform(value : String, **opts) : String
    value
  end

  def self.__arg_validate(value : String, **opts) : Bool | String
    NAME_RE.matches?(value) || "#{value} is not a valid environment variable name"
  end

  def self.__arg_complete(prefix : String, **opts) : Symbol
    :envvar # sentinel handled by shell renderers
  end
end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: EnvVar synthetic type"
```

---

## Phase 17: Shell-completion install flag

### Task 17.1: `--shell-completion <shell>` interception

**Files:**
- Create: `src/shell-auto_complete/completion/install_flag.cr`
- Modify: `src/shell-auto_complete/command.cr` (`dispatch`)
- Create: `spec/shell-auto_complete/completion/install_flag_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command InstallCli, name: "icli", description: "x" do
  flag foo : String?, "--foo", "f"
end

describe "--shell-completion handler" do
  it "writes the bash script to stdout when piped" do
    out = IO::Memory.new
    err = IO::Memory.new
    InstallCli.dispatch(["--shell-completion", "bash"], stdout: out, stderr: err)
    out.to_s.should contain("complete -F _icli icli")
  end

  it "writes the install example to stderr when stdout is a tty" do
    # simulate via stub: pass an IO that reports tty? true
    tty_out = TtyIO.new
    err = IO::Memory.new
    InstallCli.dispatch(["--shell-completion", "bash"], stdout: tty_out, stderr: err)
    err.to_s.should contain("eval")
    tty_out.bytes_written.should eq(0)
  end

  it "writes the shell list to stderr when shell is missing/invalid" do
    err = IO::Memory.new
    InstallCli.dispatch(["--shell-completion"], stdout: IO::Memory.new, stderr: err)
    err.to_s.should contain("bash")
    err.to_s.should contain("zsh")
    err.to_s.should contain("fish")
  end
end
```

`TtyIO` is a tiny helper test class that returns `true` from `tty?`.

- [ ] **Step 2: Implement install-flag handler**

```crystal
module Shell::AutoComplete::Completion::InstallFlag
  SHELLS = %w[bash zsh fish]

  def self.handle(klass, argv : Array(String), stdout : IO, stderr : IO) : Bool
    flag_name = klass.shell_completion_flag_name
    return false unless argv.first? == flag_name
    shell = argv[1]?
    unless shell && SHELLS.includes?(shell)
      stderr.puts "Supported shells: #{SHELLS.join(", ")}"
      stderr.puts %(Example: eval "$(#{klass.command_name} #{flag_name} bash)")
      Process.exit(1)
    end
    script = klass.completion_script(shell.to_sym)
    if stdout.responds_to?(:tty?) && stdout.tty?
      stderr.puts %(Add this to your shell rc: eval "$(#{klass.command_name} #{flag_name} #{shell})")
      Process.exit(1)
    end
    stdout.print script
    true
  end
end
```

(Add `shell_completion_flag_name` to `Command` defaulting to `"--shell-completion"`, override via macro.)

- [ ] **Step 3: Update `dispatch`** to call the install-flag handler before flag parsing.

- [ ] **Step 4: Add a `completion_script(shell : Symbol) : String` stub on `Command`** that returns a placeholder. Real implementation follows in Phase 18.

- [ ] **Step 5: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: --shell-completion install flag dispatcher"
```

### Task 17.2: `shell_completion_flag` macro for custom flag name

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command CustomFlagCli, name: "c", description: "x" do
  shell_completion_flag "--gen-completion"
  flag foo : String?, "--foo", "f"
end

it "uses the custom flag name" do
  CustomFlagCli.shell_completion_flag_name.should eq("--gen-completion")
end
```

- [ ] **Step 2: Implement**

```crystal
macro shell_completion_flag(name)
  def self.shell_completion_flag_name : String
    {{name}}
  end
end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: shell_completion_flag macro for custom flag name"
```

### Task 17.3: Reserve the configured shell-completion flag

- [ ] **Step 1: Failing test** asserting compile error when user declares a flag with the same name as the configured shell-completion flag.

- [ ] **Step 2: Implement** — the `flag` macro reads the class-level `shell_completion_flag_name` if available, and rejects the matching string. (This requires the `flag` macro to be evaluated after `shell_completion_flag` — which is natural since both live in the `command` block, evaluated top-to-bottom.)

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: reserve configured shell-completion flag name"
```

---

## Phase 18: Bash completion script + runtime dispatch

### Task 18.1: Bash script renderer (subcommand + static flag names)

**Files:**
- Create: `src/shell-auto_complete/completion/renderer.cr`
- Create: `src/shell-auto_complete/completion/bash.cr`
- Create: `spec/shell-auto_complete/completion/bash_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command BashRoot, name: "myapp", description: "demo" do
  flag verbose : Bool = false, "--verbose", "v"
end

describe "Bash renderer" do
  it "emits a complete -F directive" do
    script = BashRoot.completion_script(:bash)
    script.should contain("complete -F _myapp myapp")
  end

  it "includes the long flag" do
    script = BashRoot.completion_script(:bash)
    script.should contain("--verbose")
  end

  it "includes --no-verbose for negatable Bool" do
    BashRoot.completion_script(:bash).should contain("--no-verbose")
  end
end
```

- [ ] **Step 2: Implement bash renderer**

The bash script always delegates to a runtime callback so smart alias filtering, `@[Flags]` enum trailing-comma completion, and dynamic completers can run uniformly. Static structure is encoded in the callback's branching logic.

```crystal
module Shell::AutoComplete::Completion::Bash
  def self.render(klass) : String
    cmd = klass.command_name
    fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
    String.build do |s|
      s << <<-BASH
      #{fn}() {
        local out
        out=$(#{cmd} __complete "$COMP_CWORD" "${COMP_WORDS[@]}")
        COMPREPLY=( $(compgen -W "$out" -- "${COMP_WORDS[COMP_CWORD]}") )
      }
      complete -F #{fn} #{cmd}
      BASH
    end
  end
end
```

The list of supported flag names lives in the binary's `__complete` handler, not in the bash script — which keeps the script minimal and pushes the smart-alias / trailing-comma logic into Crystal.

- [ ] **Step 3: Wire `completion_script` to dispatch to the bash renderer for `:bash`.**

- [ ] **Step 4: The test above asserts that the script contains specific strings (`--verbose`, `--no-verbose`).** Since the script delegates to runtime, those strings won't appear in the generated bash. Adjust the test: assert that the binary's `__complete` output contains them given an empty current-word.

```crystal
it "emits --verbose and --no-verbose when completing flag names" do
  out = IO::Memory.new
  BashRoot.dispatch(["__complete", "1", "myapp", ""], stdout: out)
  out.to_s.lines.should contain("--verbose")
  out.to_s.lines.should contain("--no-verbose")
end
```

- [ ] **Step 5: Implement runtime `__complete` mode** (basic version).

```crystal
module Shell::AutoComplete::Completion::Dispatcher
  def self.handle(klass, argv : Array(String), stdout : IO) : Nil
    return unless argv[0]? == "__complete"
    cword = argv[1].to_i
    words = argv[2..]
    ctx = CompletionContext.new(words, cword)
    candidates = klass.completion_candidates(ctx)
    candidates.each { |c| stdout.puts c.is_a?(Candidate) ? c.value : c }
  end
end
```

- [ ] **Step 6: Add `completion_candidates` class method via the `inherited` macro** that enumerates flag names appropriate for the current slot.

- [ ] **Step 7: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: bash renderer + runtime __complete dispatch (flag names)"
```

### Task 18.2: Smart alias filtering

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command AliasComp, name: "ac", description: "x" do
  flag dryrun : Bool = false, %w(--dryrun --dry-run), "d"
end

describe "smart alias filtering" do
  it "hides --dry-run when --dryrun also matches the prefix" do
    out = IO::Memory.new
    AliasComp.dispatch(["__complete", "1", "ac", "--dry"], stdout: out)
    lines = out.to_s.lines
    lines.should contain("--dryrun")
    lines.should_not contain("--dry-run")
  end

  it "shows --dry-run when --dryrun does not match" do
    out = IO::Memory.new
    AliasComp.dispatch(["__complete", "1", "ac", "--dry-"], stdout: out)
    lines = out.to_s.lines
    lines.should contain("--dry-run")
    lines.should_not contain("--dryrun")
  end
end
```

- [ ] **Step 2: Implement** — in `completion_candidates`, when emitting flag names, group by canonical and filter aliases per the spec rule.

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: smart alias filtering at completion time"
```

### Task 18.3: `@[Flags]` enum trailing-comma completion

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command FlagsComp, name: "fc", description: "x" do
  flag perms : Perm = Perm::None, "--perms", "p"
end

it "offers remaining cases after a trailing comma" do
  out = IO::Memory.new
  FlagsComp.dispatch(["__complete", "2", "fc", "--perms", "read,"], stdout: out)
  lines = out.to_s.lines
  lines.should contain("read,write")
  lines.should contain("read,execute")
  lines.should_not contain("read,read")
end
```

- [ ] **Step 2: Implement** — extend the flag-value-completion branch of `completion_candidates`: detect `@[Flags]` enum + trailing comma, and emit `prefix + case` for each case not already present.

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: @[Flags] enum trailing-comma completion"
```

### Task 18.4: Path/File/Dir/EnvVar shell-native sentinels

- [ ] **Step 1: Failing test**

```crystal
Shell::AutoComplete.command PathComp, name: "pc", description: "x" do
  flag input : Path?, "--input", "i"
end

it "emits a file-completion sentinel for Path-typed flag values" do
  out = IO::Memory.new
  PathComp.dispatch(["__complete", "2", "pc", "--input", ""], stdout: out)
  out.to_s.should contain("__SAC_FILES__")
end
```

The renderer translates `__SAC_FILES__` into shell-native file completion in the bash script:

```bash
if [[ "$out" == "__SAC_FILES__" ]]; then
  COMPREPLY=( $(compgen -f -- "${COMP_WORDS[COMP_CWORD]}") )
  return
fi
```

- [ ] **Step 2: Implement sentinel emission + bash script handling.**

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: file/envvar shell-native completion sentinels"
```

---

## Phase 19: Zsh and Fish renderers

### Task 19.1: Zsh renderer

**Files:**
- Create: `src/shell-auto_complete/completion/zsh.cr`
- Create: `spec/shell-auto_complete/completion/zsh_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
it "renders a zsh _arguments-style script" do
  script = BashRoot.completion_script(:zsh)
  script.should contain("compdef _myapp myapp")
  script.should contain("_myapp()")
end
```

- [ ] **Step 2: Implement**

```crystal
module Shell::AutoComplete::Completion::Zsh
  def self.render(klass) : String
    cmd = klass.command_name
    fn = "_#{cmd.gsub(/[^A-Za-z0-9_]/, "_")}"
    String.build do |s|
      s << <<-ZSH
      #{fn}() {
        local -a out
        IFS=$'\\n' out=( $(#{cmd} __complete "$CURRENT" "${words[@]}") )
        _describe 'option' out
      }
      compdef #{fn} #{cmd}
      ZSH
    end
  end
end
```

Descriptions on candidates are passed as `value:description` lines from the binary.

- [ ] **Step 3: Update the runtime dispatcher** to emit `value\tdescription` lines when descriptions are present.

- [ ] **Step 4: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: zsh renderer"
```

### Task 19.2: Fish renderer

**Files:**
- Create: `src/shell-auto_complete/completion/fish.cr`
- Create: `spec/shell-auto_complete/completion/fish_spec.cr`

- [ ] **Step 1: Failing test**

```crystal
it "renders a fish complete script" do
  script = BashRoot.completion_script(:fish)
  script.should contain("complete -c myapp")
end
```

- [ ] **Step 2: Implement**

```crystal
module Shell::AutoComplete::Completion::Fish
  def self.render(klass) : String
    cmd = klass.command_name
    String.build do |s|
      s << <<-FISH
      function __sac_#{cmd}_complete
        set -l tokens (commandline -opc)
        set -l current (commandline -ct)
        #{cmd} __complete (math (count $tokens)) $tokens $current
      end
      complete -c #{cmd} -f -a "(__sac_#{cmd}_complete)"
      FISH
    end
  end
end
```

- [ ] **Step 3: Run, commit**

```
crystal spec
git add -A && git commit -m "feat: fish renderer"
```

---

## Phase 20: Documentation & release

### Task 20.1: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace placeholder README** with a real introduction, installation block, a complete `command...do ... end` example (the `Build` example from the spec), and a short demonstration of `--shell-completion`.

- [ ] **Step 2: Commit**

```
git add README.md
git commit -m "docs: complete README with example"
```

### Task 20.2: CHANGELOG + v0.1.0

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write CHANGELOG** with one entry summarizing what's in v0.1.0.

- [ ] **Step 2: Commit + tag**

```
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG"
git tag -a v0.1.0 -m "Initial release"
```

---

## Roadmap (out of scope for this plan)

These are deliberately not part of v0.1.0 and should be planned as follow-ups:

- POSIX-style boolean short-flag combining (`-abc` → `-a -b -c`).
- A `completeness check` warning beyond the minimal "must have content" rule.
- Symlink-aware completion installation.
- Caching / regeneration of completion scripts.
- PowerShell, nushell, elvish renderers.

---

## Self-review checklist (run after writing the plan)

- [ ] Each spec section maps to at least one task. The major chunks: `Candidate`/`CompletionContext` (1.1, 1.2), annotations (1.3), `command` macro (2.1, 2.2), `flag` macro (3.1–3.3, 7.x, 8.x, 13.x), `positional`/`positionals` (10.x, 11.x), subcommands (12.x), transformer chain (7.x), validator chain (8.x), completer chain + bundled defaults (13.1, 17–18), bundled transformers (15.x, 16.x), Bool / `--no-` (6.x), enum / `shortcut_flags` (13.x), collections + `delimiter:` / `set_operations:` (14.x), `--`-handling (10.2), help (9.x), `--shell-completion` install flag (17.x), runtime `__complete` (18.x), bash/zsh/fish renderers (18, 19), smart alias filtering (18.2), `@[Flags]` trailing-comma (18.3), `hidden:` (9.3), sub-subcommands (12.2).
- [ ] No "TBD" or "TODO" in any task body.
- [ ] Code blocks present wherever code is introduced; commands and expected outcomes are explicit.
- [ ] Method/property names stay consistent: `__arg_transform`, `__arg_validate`, `__arg_complete`; `FlagDef`, `PositionalDef`, `PositionalsDef`, `CommandDef`; `Candidate`, `CompletionContext`; `command_name`, `completion_script`, `shell_completion_flag_name`, `dispatch`.
- [ ] Sentinels (`__SAC_FILES__`) used only in Phase 18.4 and explicitly described.
