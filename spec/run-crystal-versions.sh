#!/usr/bin/env bash
#
# run-crystal-versions.sh — find the oldest Crystal release this shard supports.
#
# Sweeps Crystal releases from newest to oldest (the latest patch of each minor:
# 1.20.x, 1.19.x, 1.18.x, …), runs `crystal spec` for each inside a container
# built from spec/Dockerfile, and stops at the first release whose specs fail.
# The lowest release that still passes becomes the new minimum, written back to
# the `crystal:` constraint in shard.yml.
#
# The Docker client here targets a remote daemon over a secure (Tailscale) link.
# Two consequences shape this script:
#   * Bind mounts can't reach the local tree, so the source is sent as build
#     context and COPYed in (see spec/Dockerfile).
#   * Container stdout does not stream back to the client, but exit codes do and
#     `docker logs` retrieves output after the fact. So we run a *named*
#     container, read its exit code, and pull its output via `docker logs`.
#
# Usage:
#   spec/run-crystal-versions.sh [options] [VERSION ...]
#
# Options:
#   --floor X.Y.Z   Don't test releases older than this (default: 1.0.0).
#   --start X.Y.Z   Begin from this release instead of the newest available.
#   --keep          Keep the per-version images instead of removing them.
#   --no-write      Report the result but don't modify shard.yml.
#   -h, --help      Show this help.
#
# With explicit VERSION arguments, those exact versions are tested in the order
# given and registry discovery is skipped.
set -euo pipefail

IMAGE_REPO="crystallang/crystal"
TAG_PREFIX="shell-auto_complete-spec"
FLOOR="1.0.0"
START=""
KEEP_IMAGES=0
WRITE_SHARD=1
EXPLICIT=""

die() { echo "error: $*" >&2; exit 1; }

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --floor)    FLOOR="${2:-}"; shift 2 ;;
    --start)    START="${2:-}"; shift 2 ;;
    --keep)     KEEP_IMAGES=1; shift ;;
    --no-write) WRITE_SHARD=0; shift ;;
    -h|--help)  usage; exit 0 ;;
    --)         shift; EXPLICIT="$EXPLICIT $*"; break ;;
    -*)         die "unknown option: $1" ;;
    *)          EXPLICIT="$EXPLICIT $1"; shift ;;
  esac
done

command -v docker  >/dev/null 2>&1 || die "docker not found in PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not found in PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
DOCKERFILE="$ROOT/spec/Dockerfile"
SHARD_YML="$ROOT/shard.yml"
[ -f "$DOCKERFILE" ] || die "missing $DOCKERFILE"
[ -f "$SHARD_YML" ]  || die "missing $SHARD_YML"

# Discover the latest patch of every published minor from the Docker Hub tag
# list, newest first, filtered to >= FLOOR and (optionally) <= START.
discover_versions() {
  python3 - "$FLOOR" "$START" <<'PY'
import json, re, sys, urllib.request

def parse(v): return tuple(int(x) for x in v.split("."))

floor = parse(sys.argv[1])
start = parse(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None

latest = {}
url = "https://hub.docker.com/v2/repositories/crystallang/crystal/tags?page_size=100"
while url:
    with urllib.request.urlopen(url, timeout=30) as r:
        data = json.load(r)
    for t in data["results"]:
        m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", t["name"])
        if not m:
            continue
        mj, mn, pa = int(m[1]), int(m[2]), int(m[3])
        key = (mj, mn)
        if key not in latest or pa > latest[key]:
            latest[key] = pa
    url = data.get("next")

versions = sorted(((mj, mn, pa) for (mj, mn), pa in latest.items()), reverse=True)
for v in versions:
    if v < floor:
        continue
    if start is not None and v > start:
        continue
    print("%d.%d.%d" % v)
PY
}

versions=""
if [ -n "${EXPLICIT// /}" ]; then
  versions="$EXPLICIT"
else
  echo "Discovering Crystal releases from Docker Hub (floor ${FLOOR}${START:+, start ${START}})…" >&2
  versions="$(discover_versions)"
fi
[ -n "${versions// /}" ] || die "no candidate versions to test"

echo "Version sweep (newest → oldest):" >&2
echo "$versions" | tr ' ' '\n' | sed '/^$/d' | sed 's/^/  /' >&2
echo >&2

last_pass=""
first_fail=""

for v in $versions; do
  tag="${TAG_PREFIX}:${v}"
  cname="${TAG_PREFIX}-run-$$-${v}"

  printf '==> Crystal %s: building image (pulls base on first use)… ' "$v" >&2
  if ! docker build -q -f "$DOCKERFILE" --build-arg "CRYSTAL_VERSION=${v}" -t "$tag" "$ROOT" >/dev/null 2>build.log; then
    echo "BUILD ERROR" >&2
    sed 's/^/    /' build.log >&2 || true
    rm -f build.log
    die "image build failed for Crystal ${v} (infrastructure problem, not a spec failure)"
  fi
  rm -f build.log
  printf 'running specs… ' >&2

  docker rm -f "$cname" >/dev/null 2>&1 || true
  rc=0
  docker run --name "$cname" "$tag" >/dev/null 2>&1 || rc=$?
  out="$(docker logs "$cname" 2>&1 || true)"
  docker rm -f "$cname" >/dev/null 2>&1 || true
  [ "$KEEP_IMAGES" -eq 1 ] || docker image rm "$tag" >/dev/null 2>&1 || true

  summary="$(printf '%s\n' "$out" | grep -E '[0-9]+ examples?' | tail -n1 || true)"
  if [ "$rc" -eq 0 ]; then
    echo "PASS${summary:+  (${summary})}" >&2
    last_pass="$v"
  else
    echo "FAIL (exit ${rc})${summary:+  (${summary})}" >&2
    echo "    ---- output from Crystal ${v} ----" >&2
    printf '%s\n' "$out" | sed 's/^/    /' >&2
    echo "    ----------------------------------" >&2
    first_fail="$v"
    break
  fi
done

echo >&2
if [ -z "$last_pass" ]; then
  die "no tested Crystal release passed (newest tested release failed); shard.yml left unchanged"
fi

echo "Oldest passing Crystal release: ${last_pass}" >&2
[ -n "$first_fail" ] && echo "First failing release below it: ${first_fail}" >&2

current="$(grep -E "^crystal:" "$SHARD_YML" | head -n1 || true)"
new_line="crystal: '>= ${last_pass}'"

if [ "$WRITE_SHARD" -eq 0 ]; then
  echo "shard.yml not modified (--no-write). Would set: ${new_line}" >&2
  exit 0
fi

if [ "$current" = "$new_line" ]; then
  echo "shard.yml already pins the minimum to ${last_pass}; no change." >&2
  exit 0
fi

python3 - "$SHARD_YML" "$last_pass" <<'PY'
import re, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f:
    text = f.read()
new, n = re.subn(r"(?m)^crystal:.*$", "crystal: '>= %s'" % ver, text)
if n == 0:
    new = text.rstrip("\n") + "\ncrystal: '>= %s'\n" % ver
with open(path, "w") as f:
    f.write(new)
PY

echo "Updated shard.yml:" >&2
echo "  was: ${current:-<none>}" >&2
echo "  now: ${new_line}" >&2
