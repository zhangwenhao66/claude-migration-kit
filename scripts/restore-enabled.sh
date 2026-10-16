#!/usr/bin/env bash
# Re-enable scheduled tasks, from a list, optionally in batches.
#
# migrate.sh imports every task with enabled=false (so nothing fires during the migration) and
# writes the list of tasks that were ENABLED in the source to source-enabled-tasks-<stamp>.txt.
# This script applies a list like that, without touching lastScheduledFor / missedRunScanFloor,
# so the missed-run window stays closed and nothing is caught up retroactively.
#
# (The sibling kit claude-restore-kit also writes target-was-enabled-<stamp>.txt, because a
# migration back INTO a live account can switch the account's own routines off. Nothing here
# produces that file, so it is not mentioned below.)
#
# Either way lastScheduledFor / missedRunScanFloor are left alone, so the missed-run window stays
# closed and nothing is caught up retroactively.
#
# Usage:
#   bash restore-enabled.sh --dry-run
#   bash restore-enabled.sh --limit 10
#   bash restore-enabled.sh --only a,b,c
#   bash restore-enabled.sh --from <a list file you name>
#   bash restore-enabled.sh <path-to-any-list-file>
#
# Requires Claude Desktop to be quit (it caches scheduling state in memory).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"   # where migrate.sh wrote its artifacts
if [ ! -f "$HERE/config.sh" ]; then
  echo "config.sh not found. Copy config.example.sh to config.sh and fill it in." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$HERE/config.sh"

DRY=0; LIMIT=""; ONLY=""; LIST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --limit)   shift; LIMIT="${1:-}" ;;
    --only)    shift; ONLY="${1:-}" ;;
    --from)    shift; LIST="${1:-}" ;;
    -*)        echo "unknown option: $1" >&2; exit 1 ;;
    *)         LIST="$1" ;;
  esac
  shift
done

# --only names ids explicitly, so it does not need a list file at all.
if [ -z "${LIST}" ] && [ -z "${ONLY}" ]; then
  LIST="$(find "$ROOT" -maxdepth 1 -name 'source-enabled-tasks-*.txt' | sort | tail -1)"
fi
if [ -z "${ONLY}" ]; then
  if [ -z "${LIST}" ] || [ ! -f "${LIST}" ]; then
    echo "No list file found. Either let restore.sh write one, or name one explicitly:" >&2
    echo "  bash restore-enabled.sh --from source-enabled-tasks-<stamp>.txt   # was running on the gateway" >&2
    echo "  bash restore-enabled.sh --from <a list file you name>     # was running in the account" >&2
    echo "  bash restore-enabled.sh --only id1,id2,id3                        # exactly these" >&2
    exit 1
  fi
fi

echo "list   : ${LIST:-<none, --only was given>}"
echo "target : ${CODE_DST}/scheduled-tasks.json"
[ "${DRY}" = "1" ] && echo "mode   : DRY RUN (nothing will be written)"

if [ "${DRY}" = "0" ]; then
  # shellcheck source=/dev/null
  source "$HERE/lib-appguard.sh"
  LIVE="$(claude_app_pids | wc -l | tr -d ' ')"
  [ "${LIVE}" -eq 0 ] || { echo "Claude Desktop is still running. Quit it first (⌘Q)." >&2; exit 1; }
fi

python3 - "${CODE_DST}/scheduled-tasks.json" "${LIST:-}" "${DRY}" "${LIMIT}" "${ONLY}" <<'PY'
import json, sys, os

tasks_file, list_file, dry, limit, only = sys.argv[1:6]
dry = dry == "1"

# --- read the wanted list: one task id per line, "- id" tolerated, "#" and blank lines skipped
wanted = []
if list_file:
    for line in open(list_file, encoding="utf-8"):
        line = line.rstrip("\n").strip()
        if not line or line.startswith("#"):
            continue
        if line.endswith(":") and " " in line:      # a section header like "added from ...:"
            continue
        if line.startswith("- "):
            line = line[2:].strip()
        if line:
            wanted.append(line)

# --only means exactly these ids. It must NOT be intersected with the list first: the ids a user
# needs to restore after a merge are the account's own, which by definition are not in the
# gateway's enabled list. (It used to filter the list by the selection, so --only silently
# enabled nothing and still exited 0.)
if only:
    wanted = [x.strip() for x in only.split(",") if x.strip()]

if limit:
    try:
        n = int(limit)
    except ValueError:
        print("--limit needs a number", file=sys.stderr); sys.exit(1)
    wanted = wanted[:n]

d = json.load(open(tasks_file))
tasks = d.get("scheduledTasks", [])
by_id = {t.get("id"): t for t in tasks}

missing = [w for w in wanted if w not in by_id]
to_on   = [w for w in wanted if w in by_id and not by_id[w].get("enabled")]
already = [w for w in wanted if w in by_id and by_id[w].get("enabled")]

print(f"  in list     : {len(wanted)}")
print(f"  will enable : {len(to_on)}")
print(f"  already on  : {len(already)}")
if missing:
    print(f"  NOT in target ({len(missing)}) — check these are real task ids:")
    for m in missing[:20]:
        print("    -", m)

if dry:
    print("\n  would enable:")
    for w in to_on:
        print("    -", w)
    print("\n(dry run — nothing written)")
    sys.exit(0)

if not to_on:
    if wanted:
        print("\nNothing to do — none of the requested ids exist in the target, or all are already on.")
    else:
        print("\nNothing to do — the list was empty.")
    sys.exit(0)

for w in to_on:
    by_id[w]["enabled"] = True

tmp = tasks_file + ".tmp"
json.dump(d, open(tmp, "w"), ensure_ascii=False, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, tasks_file)

# safety: every enabled task must still carry a missed-run floor, or it may catch up
nofloor = [t["id"] for t in tasks if t.get("enabled") and not t.get("missedRunScanFloor")]
if nofloor:
    print(f"\n  WARNING: {len(nofloor)} enabled task(s) have no missedRunScanFloor — they may catch up:")
    for i in nofloor[:20]:
        print("    -", i)

# how many enabled tasks are still off
still_off = [t["id"] for t in tasks if not t.get("enabled")]
print(f"\n  enabled now : {sum(1 for t in tasks if t.get('enabled'))} / {len(tasks)}")
print(f"  still off   : {len(still_off)}")
print("\nReopen Claude Desktop and check the Routines list.")
if still_off:
    print("Run this script again to enable more, or use --limit/--only to stage it.")
PY
