# Subcommand `--help` Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `mycli <subcommand> --help` show the subcommand's help (and `mycli <sub> <subsub> --help` show the sub-subcommand's help), instead of always showing the root command's help.

**Architecture:** A two-line reordering inside `Command.dispatch`. Move subcommand routing *before* the `--help`/`-h` interception. The current dispatch sequence intercepts `--help` first, so it always fires for the topmost class regardless of which command the flag was intended for. After the fix, an explicit subcommand name in `argv[0]` short-circuits to that subcommand's `dispatch`, which then runs its own `--help` check.

**Tech Stack:** Crystal 1.20.1+. No new dependencies.

---

## Root cause

Current `dispatch` (`src/shell-auto_complete/command.cr`):

```crystal
def self.dispatch(argv, stdout = STDOUT, stderr = STDERR) : ::Shell::AutoComplete::Command?
  return nil if Completion::Dispatcher.handle(self, argv, stdout)
  return nil if Completion::InstallFlag.handle(self, argv, stdout, stderr)

  # ← bug: --help is intercepted BEFORE subcommand routing
  if argv.includes?("--help") || argv.includes?("-h")
    stdout.puts help
    return nil
  end

  # Subcommand routing
  if !argv.empty? && (sub = SUBCOMMANDS.find { |(name, _)| name == argv[0] })
    return sub[1].dispatch(argv[1..], stdout: stdout, stderr: stderr)
  end
  ...
end
```

So `mycli scan --help`:
- argv = `["scan", "--help"]`
- The `argv.includes?("--help")` check matches and prints the root command's help.
- Subcommand routing is never reached.

## Fix

Swap the order. After the hidden-mode handlers (`__complete`, install flag), check for subcommand routing first. Only check `--help` if no subcommand matched (i.e., we're at the level the user actually means).

After the fix:

```crystal
def self.dispatch(argv, stdout = STDOUT, stderr = STDERR) : ::Shell::AutoComplete::Command?
  return nil if Completion::Dispatcher.handle(self, argv, stdout)
  return nil if Completion::InstallFlag.handle(self, argv, stdout, stderr)

  # Subcommand routing first — let the matched subcommand handle its own --help.
  if !argv.empty? && (sub = SUBCOMMANDS.find { |(name, _)| name == argv[0] })
    return sub[1].dispatch(argv[1..], stdout: stdout, stderr: stderr)
  end

  # No subcommand matched — handle --help at THIS level.
  if argv.includes?("--help") || argv.includes?("-h")
    stdout.puts help
    return nil
  end

  # Reject unknown subcommand only when subcommands are declared
  if !SUBCOMMANDS.empty? && !argv.empty?
    raise ParseError.new("unknown subcommand: #{argv[0]}")
  end

  inst = parse(argv)
  inst.run
  inst
end
```

This makes `--help` walk down the routing tree exactly like any other argv: each level routes to a subcommand (if matched) or handles the remaining argv (including `--help`) itself.

## Behavior matrix after the fix

| Invocation | Behavior |
|---|---|
| `mycli --help` | argv[0]=`"--help"` not a subcommand → falls through to `--help` check at root → prints root help |
| `mycli scan` | argv[0]=`"scan"` matches subcommand → routes to `ScanCli.dispatch([])` → parses + runs |
| `mycli scan --help` | routes to `ScanCli.dispatch(["--help"])` → matches `--help` check → prints scan's help |
| `mycli scan deep --help` | routes through to `ScanDeep.dispatch(["--help"])` → prints scan-deep's help |
| `mycli unknown --help` | argv[0]=`"unknown"` is not a known subcommand; falls through to `--help` check → prints root help (reasonable default) |
| `mycli --help scan` | argv[0]=`"--help"` is not a subcommand → `--help` check matches → prints root help |
| `mycli scan --flag x --help` | routes to scan; scan's `--help` check matches → prints scan's help |

## Task: implement the reorder + tests

**Files:**
- Modify: `src/shell-auto_complete/command.cr` — reorder `dispatch`.
- Modify: `spec/shell-auto_complete/subcommand_spec.cr` — add subcommand-help tests.

- [ ] **Step 1: Write failing tests**

Append to `spec/shell-auto_complete/subcommand_spec.cr` (alongside the existing subcommand tests, which already define `SubChild`, `SubParent`, `Leaf`, `Middle`, `Root`):

```crystal
describe "subcommand --help routing" do
  it "subcommand --help prints the subcommand's help, not the root's" do
    out = IO::Memory.new
    SubParent.dispatch(["child", "--help"], stdout: out)
    text = out.to_s
    text.should contain("Usage: child")
    text.should contain("child command")
    text.should_not contain("Usage: parent")
  end

  it "subcommand -h does the same" do
    out = IO::Memory.new
    SubParent.dispatch(["child", "-h"], stdout: out)
    text = out.to_s
    text.should contain("Usage: child")
  end

  it "sub-subcommand --help prints the leaf's help" do
    out = IO::Memory.new
    Root.dispatch(["middle", "leaf", "--help"], stdout: out)
    text = out.to_s
    text.should contain("Usage: leaf")
    text.should_not contain("Usage: root")
    text.should_not contain("Usage: middle")
  end

  it "root --help still prints the root's help" do
    out = IO::Memory.new
    SubParent.dispatch(["--help"], stdout: out)
    text = out.to_s
    text.should contain("Usage: parent")
  end

  it "unknown first token + --help still prints the root's help" do
    out = IO::Memory.new
    SubParent.dispatch(["bogus", "--help"], stdout: out)
    text = out.to_s
    text.should contain("Usage: parent")
  end

  it "subcommand --help with extra args ignores them" do
    out = IO::Memory.new
    SubParent.dispatch(["child", "--help", "--value", "x"], stdout: out)
    text = out.to_s
    text.should contain("Usage: child")
  end
end
```

- [ ] **Step 2: Run, confirm tests fail with current `dispatch` order**

```sh
crystal spec spec/shell-auto_complete/subcommand_spec.cr
```

Expected: the new tests fail (they receive root help where subcommand help was expected).

- [ ] **Step 3: Reorder `dispatch` in `command.cr`**

Inside the `macro inherited` block, locate:

```crystal
def self.dispatch(argv : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : ::Shell::AutoComplete::Command?
  return nil if ::Shell::AutoComplete::Completion::Dispatcher.handle(self, argv, stdout)
  return nil if ::Shell::AutoComplete::Completion::InstallFlag.handle(self, argv, stdout, stderr)
  if argv.includes?("--help") || argv.includes?("-h")
    stdout.puts help
    return nil
  end
  # ... subcommand routing follows ...
```

Move the `--help` check to *after* the subcommand-routing block (which currently sits a few lines below). The resulting structure:

```crystal
def self.dispatch(argv : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : ::Shell::AutoComplete::Command?
  return nil if ::Shell::AutoComplete::Completion::Dispatcher.handle(self, argv, stdout)
  return nil if ::Shell::AutoComplete::Completion::InstallFlag.handle(self, argv, stdout, stderr)

  if !argv.empty? && (sub = SUBCOMMANDS.find { |(name, _)| name == argv[0] })
    return sub[1].dispatch(argv[1..], stdout: stdout, stderr: stderr)
  end

  if argv.includes?("--help") || argv.includes?("-h")
    stdout.puts help
    return nil
  end

  if !SUBCOMMANDS.empty? && !argv.empty?
    raise ::Shell::AutoComplete::ParseError.new("unknown subcommand: #{argv[0]}")
  end

  inst = parse(argv)
  inst.run
  inst
end
```

(Read the existing file to confirm exact spacing/whitespace and preserve any other dispatch checks.)

- [ ] **Step 4: Run, confirm green**

```sh
crystal spec
```

Expected: all 6 new tests pass, all existing tests still pass (181 + 6 = 187 examples, 0 failures).

- [ ] **Step 5: Update CHANGELOG**

Add to `CHANGELOG.md`'s v0.1.0 "Added" section (or under a new "Fixed" subsection at the top):

```
### Fixed

- `<subcommand> --help` now prints the subcommand's help instead of the root command's. Sub-subcommands work the same way: `<parent> <child> --help` routes through to the leaf command's help text.
```

- [ ] **Step 6: Commit**

```sh
git add src/shell-auto_complete/command.cr spec/shell-auto_complete/subcommand_spec.cr CHANGELOG.md
git commit -m "fix: subcommand --help routes to the subcommand, not the root"
```

- [ ] **Step 7: Move the v0.1.0 tag forward**

```sh
git tag -d v0.1.0
git tag -a v0.1.0 -m "Initial release"
```

(The local tag is unpushed, so re-tagging is non-destructive.)

## Risk assessment

- **Backwards compatibility**: low risk. The only observable change is that `<sub> --help` now does something useful instead of something confusing. No working program relies on the broken behavior.
- **Interaction with other dispatch checks**: the hidden-mode handlers (`__complete`, install flag) still run first, so completion and the install flag continue to work at any level.
- **Unknown subcommand + `--help`**: falls through to root help, which is reasonable. If a user wants strict rejection, they can run without `--help`; that path is unchanged.

## Out of scope

- Help text doesn't yet honor `header:`/`footer:`/`usage:` overrides on `command` annotations. That's already the case and isn't a regression.
- A "global flags" concept where parent flags are inherited by subcommands isn't planned; each command class defines its own flags independently. The spec doesn't promise inheritance.
