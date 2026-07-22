# Consumer upgrade to shell-auto_complete 2.4.0

All eleven consumer repos are upgraded. Changes are **in the working trees, uncommitted and
unpushed** — review each with `git diff`, except `wordgame.cr`, which has no git history at all
(zero commits, nothing tracked, no remote), so there is nothing to diff against.

Every repo now pins `~> 2.4`. Six previously had **no constraint at all**, and `hoard.cr` was
capped at `~> 2.0.0`, which had been silently blocking every update since 2.1.0.

## Status

| Repo | Lock | Files | Specs | Headline |
|---|---|---|---|---|
| hoard.cr | 2.0.1 → 2.4.0 | 18 M, 2 A | 642 / 0 | −238/+157 lines; 8 hand parsers deleted |
| transmission-utils.cr | 2.2.1 → 2.4.0 | 23 M, 1 A | 549 / 0 | 8 silent-wrong-value bugs fixed |
| stashapp-cli.cr | 2.2.1 → 2.4.0 | 28 M, 1 A | 211 / 1\* | 3 live bugs fixed |
| hf.cr | 2.2.1 → 2.4.0 | 7 M, 2 A | 326 / 0 | completion-corrupting bug fixed |
| torinfo.cr | 2.2.1 → 2.4.0 | — | 182 / 0 | 7 Bool switches → 1 enum |
| wordgame.cr | 2.2.1 → 2.4.0 | — | 130 / 0 | 4 filenames now complete |
| scroll.cr | 2.3.0 → 2.4.0 | 4 M | 116 / 0 | completion-corrupting bug fixed |
| ldap-invite.cr | 2.2.1 → 2.4.0 | — | 52 / 0 | `common_flag` + `before_run` + live completer |
| hostfw.cr | 2.2.1 → 2.4.0 | — | 46 / 2\* | 3 path flags typed |
| urlinfo.cr | 2.2.1 → 2.4.0 | — | 26 / 0 | `shortcut_flags:`, `range:` |
| jqless.cr | 2.2.1 → 2.4.0 | — | 8 / 0 | hand-rolled `--version` deleted |

\* **Both failure counts are pre-existing and unrelated**, each verified by stashing the work and
reproducing at clean HEAD. stashapp: `find_filter` unconditionally sets `per_page` so it can never
be empty (`selection.cr:193`). hostfw: two YAML fixture parse errors (`found unexpected ':'`).

## Bugs fixed in the consumers

### Completion silently corrupted (hf.cr, scroll.cr)

Both mutated `ARGV` before `dispatch`, not accounting for the shell completion callback arriving
through that same argv as `__complete <cword> <words...>`. Dropping or expanding a token shifted
the word list without adjusting `cword`, so the wrong slot got completed. Invisible to `--help`
testing; only affected users who had installed completions.

hf.cr deleted all pre-dispatch rewriting — `--version` now comes from the shard's intercept and
`--verbose` became a real flag via `common_flag` + `before_run`, leaving `dispatch(ARGV.dup)` as
the whole entry point. scroll.cr passes a completion callback through untouched; the agent proved
its regression spec fails without the guard (`got: []`) before restoring it.

### Silent wrong-value acceptance (transmission-utils.cr)

Six flags accepted garbage and quietly substituted a default. Worst was `--state`, whose
`parse_state` returned `nil` for unrecognised input, so `trr list --state wat` applied **no filter
at all** and listed everything. Also `--profile` (→ `Obligation`), `--seed-discharge` and
`--discharge` (→ `Both`), `--sort` (→ sorted by id), `--format`, and `--color-depth`. All now
enum- or `choices:`-typed and rejected by name. `--state` still accepts its old lenient spellings,
so no input was narrowed.

`watch --no-color` also auto-generated a nonsense `--no-no-color`, which the agent confirmed the
baseline binary really did accept.

### Error handling (stashapp-cli.cr)

Two doubled prefixes (`--map: --map argument must be 'SRC:DST'`) — the literals began with the flag
name while the shard already prepends it. And `scene scan --after` raised `StashAppError` from its
transform, escaping the parser's conversion and surfacing as a raw exception. Each fix was reverted
in turn to confirm its spec fails without it.

### Misleading and missing validation

`hoard --attempts`-style unbounded numerics gained `range:` across several repos; hoard's checks now
fire at parse time before any database connection. `wordgame --attempts 0` reported a misleading
"Try another --seed" late in generation and now fails immediately. `hostfw`, `hoard`, and others
replaced hand-written runtime checks with `range:`, `min:`, and `Bool?` tri-state.

## Completion coverage

The dominant gap was path-shaped values typed as `String`, which silently offered nothing. Roughly
60 flags and positionals were retyped across the eleven repos, and with them went the hand-written
completer methods that existed only to emit filesystem directives.

`Types::DirPath` — added in 2.4.0 in response to this audit — covers what previously blocked those
deletions: a directory that need not exist locally, on a daemon's host or created later by
`mkdir_p`. `Dir` would reject valid input; `Path` would offer files alongside directories. Used in
transmission-utils (7 flags), stashapp-cli (`--template-dir`, `--dest`), hoard (`--root`), and
hostfw (`state_dir`).

Fixed-value `String` flags gained `choices:` or enum types throughout. torinfo's headline result:
`--fields name,cr<TAB>` now offers `name,created-by name,created-on` instead of clobbering the
token — the delimiter-aware completion its hand-written completer never did.

## Deviations from instructions — worth your review

Agents were told to skip what `build` + specs could not verify. Several pushed back on my
instructions, correctly:

- **No `URI` retyping anywhere** (urlinfo positionals, ldap-invite `--server`). `URI.parse` raises
  `URI::Error`, which is not an `ArgumentError`, so the shard's transform rescue misses it — I
  confirmed `--s http://ex.com:abc` produces an unhandled exception with a stack trace. `URI.parse`
  is also lenient enough that `not a url` and `%%%` parse fine, so the type buys almost no
  validation. ldap-invite got the intended benefit safely via `validate_with:`.
- **transmission-utils recommends against** collapsing `--json` (11×) and `--dry-run` (6×) into
  `common_flag`: all 17 descriptions differ meaningfully, so they share a spelling without being
  duplication. Only `--config` was byte-identical across all 11 sites. It also used a lazy memoized
  module rather than `before_run` for `load_config`, since `before_run` runs eagerly and would read
  config for commands that never consult it.
- **stashapp corrected two of its own audit findings**: `map.cr --to` is a *server-side* path where
  local completion would offer the wrong tree, and `--image-chooser` is a shell command, not a path.
  It kept `Root.complete_path` because my instructions conflicted — the polymorphic id-or-path
  positionals must stay `String`, and staying `String` is exactly what still needs that completer.
- **hf declined `Types::Date`** for `--after`/`--before`: that type parses UTC while hf parses
  localtime, so switching would shift every date boundary by the UTC offset. Used `matches:` instead.
- **hf and stashapp kept completion without validation** on vocabularies authored outside their
  Crystal source (`--status`, `--resolution`, `--gender`, `--missing`, `--sort`, `--format`), where
  a guessed `choices:` list would reject valid input the server accepts.
- **Three entry points were split** into `src/main.cr` (hostfw, ldap-invite, urlinfo). All three
  called `dispatch(ARGV)` at the bottom of `src/cli.cr`, so any spec requiring the CLI would
  dispatch against the spec runner's own ARGV. torinfo and wordgame already used this layout.

### Deferred

- **hoard** — the `before_run` refactor absorbing `Config.load`/`DB.connect` from 10 `run` methods
  needs a live PostgreSQL to verify. Would save ~30 lines.
- **stashapp** — `before_run` for the ~35 `build_cli` openings, because `immediate:` handlers fire
  *before* `before_run` and would still need direct calls.
- **transmission** — 5 verb-in-a-positional commands: no specs cover their routing and several take
  variadic positionals where later elements are not verbs. These want real subcommands.

## Behavior changes to be aware of

- `hoard find --not-ignored` is gone; the `Bool?` tri-state spells it `--no-ignored`. README updated.
- `hostfw -C /nonexistent` now exits **1** (`--config-dir: directory does not exist`) instead of
  **2** via `Config.load`. Nothing tests exit codes and the README doesn't document them, but the
  `src/cli.cr` comment reserves 2 for "invalid config". Switching `config_dir` to `DirPath?` would
  restore the old code if you want it.
- `jqless --version` prints `jqless 1.0.1` rather than bare `1.0.1`, and no longer appears in
  `--help` (it is an intercept, not a declared flag).
- torinfo's enum shortcut switches (`--json` etc.) no longer appear in `--help`, since the shard
  doesn't list generated switches; the description now spells them out so they stay discoverable.

## Shard bugs found

Two are fixed on branch `fix/remapped-type-validation-and-defaults` (`35f7abb`, 531 specs, 0
failures, **unpushed**). Five more are confirmed and unfixed. All predate 2.4.0.

**Fixed:**

1. Synthetic type validators never ran on flags — `PositiveInt`, `NonNegativeInt`, `Percentage`,
   `EnvVar` resolve `__arg_validate` against the *storage* type, which has none, so `--limit 0`
   on a `PositiveInt` flag parsed fine. Positionals were always correct.
2. Storage-remapped flags dropped declared defaults, so
   `flag root : Types::DirPath = Path.new("/")` failed to compile. hostfw hit this and worked
   around it with nilable flags plus resolver methods; those six lines collapse once it ships.

**Confirmed, unfixed:**

3. **Subcommand completion dies when any flag precedes the cursor.** `probe m<TAB>` → `mid`, but
   `probe --verbose m<TAB>` → nothing, and `probe --verbose mid <TAB>` → nothing instead of `leaf`.
   Caps the payoff of hf's `--verbose` refactor.
4. **Variadic positionals silently ignore `transform_with:`/`validate_with:`.** The macro accepts
   the options and does nothing — a scalar transformed to `AA` while the variadic left `bb`, `cc`
   untouched.
5. **`choices:` given a constant reference completes nothing.** Validation works; completion is
   silently empty. Only array literals complete, so a "tidy-up" that extracts the list to a
   constant silently breaks completion.
6. **Collection `choices:` has no delimiter-aware completion** — `--cols 'id,'` returns nothing,
   which is why stashapp had to hand-write `complete_column_list`.
7. **The stock `URI` transform doesn't wrap `URI::Error`**, so a malformed URI escapes as an
   unhandled exception instead of a clean parse error.

Two smaller notes: `common_flag` must be called at **top level** (it defines its replay macro
wherever it expands, so a catalog nested in a module is invisible to commands in that same
module) — two agents hit this independently, so it wants a doc line. And a type-level
`__arg_transform` returning `self` breaks the positional macro, which splices the return type
verbatim and emits `property! verb : ::self`; return types must be written fully qualified.

## Environment

Not caused by these changes: the nix-built Crystal here cannot find Homebrew's libraries, so most
repos fail at the **link** step. Every agent confirmed the baseline failed identically before
touching any source. Builds and specs need:

```
LIBRARY_PATH=/opt/homebrew/opt/sqlite/lib:/opt/homebrew/opt/zlib/lib:/opt/homebrew/opt/libxml2/lib:$(xcrun --show-sdk-path)/usr/lib
```
