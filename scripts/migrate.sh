#!/usr/bin/env bash
# ============================================================================
# Claude Desktop account/deployment migration.
#
#   bash migrate.sh check   read-only preflight (safe while Claude is running)
#   bash migrate.sh test    backup + copy the 20 most recent non-routine sessions
#   bash migrate.sh all     backup (reused) + remaining sessions + tasks + Cowork
#
# Safety design:
#   * copy only — the source partition is never modified, moved or deleted
#   * a verified backup before anything is written
#   * scheduled tasks imported with enabled=false and the missed-run window stamped
#   * a manifest per phase, so rollback.sh can undo precisely
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"   # generated artifacts (backups, manifests, logs) land here
if [ ! -f "$HERE/config.sh" ]; then
  echo "config.sh not found." >&2
  echo "  1. Run:  bash \"$HERE/find-partitions.sh\"" >&2
  echo "  2. Then: cp \"$HERE/config.example.sh\" \"$HERE/config.sh\"  and fill it in." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$HERE/config.sh"

MODE="${1:-check}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$ROOT/migration-$MODE-$STAMP.log"
MAN_S="$ROOT/manifest-sessions.txt"
MAN_C="$ROOT/manifest-cowork.txt"

die() { echo "ABORT: $*" >&2; exit 1; }
cnt() { find "$1" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' '; }

echo "=== Claude migration · mode=${MODE} · $(date)"
echo "    source: ${CODE_SRC}"
echo "    target: ${CODE_DST}"

case "${MODE}" in check|test|all) ;; *) die "usage: migrate.sh check|test|all" ;; esac

# ---------------------------------------------------------------- preflight
[ -d "${CODE_SRC}" ] || die "source partition not found: ${CODE_SRC}"
[ -d "${CODE_DST}" ] || die "target partition not found: ${CODE_DST} (open Claude once with the new account)"
[ "${CODE_SRC}" != "${CODE_DST}" ] || die "source and target are the same"

SRC_N="$(cnt "${CODE_SRC}")"; DST_N="$(cnt "${CODE_DST}")"
echo "    sessions: source=${SRC_N} target=${DST_N}"
[ "${SRC_N}" -gt 0 ] || die "source has no sessions"

TASK_SRC="${CODE_SRC}/scheduled-tasks.json"
TASK_DST="${CODE_DST}/scheduled-tasks.json"
[ -f "${TASK_SRC}" ] || die "source has no scheduled-tasks.json"
TASK_SRC_N="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['scheduledTasks']))" "${TASK_SRC}")"
TASK_DST_N="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['scheduledTasks']))" "${TASK_DST}")"
echo "    tasks   : source=${TASK_SRC_N} target=${TASK_DST_N}"
[ "${TASK_DST_N}" -eq 0 ] || die "target already has ${TASK_DST_N} tasks; importing would overwrite them. Resolve manually."

if [ "${MIGRATE_COWORK:-0}" = "1" ]; then
  [ -d "${COW_SRC}" ] || die "Cowork source not found: ${COW_SRC}"
  [ -d "${COW_DST}" ] || die "Cowork target not found: ${COW_DST}"
  echo "    cowork  : source=$(cnt "${COW_SRC}")"
fi

AVAIL_G="$(df -g "$HOME" | awk 'NR==2{print $4}')"
echo "    free    : ${AVAIL_G} GB"
[ "${AVAIL_G}" -ge 60 ] || die "need at least 60 GB free"

echo "OK preflight"
[ "${MODE}" = "check" ] && { echo "(read-only; nothing changed)"; exit 0; }

# ------------------------------------------------------------- app guard
# The app must be fully quit: it caches scheduling state in memory and writes it back on exit.
if pgrep -f "Applications/Claude.app" >/dev/null 2>&1; then
  LIVE=0
  for p in $(pgrep -f "Applications/Claude.app" 2>/dev/null || true); do
    cmd="$(ps -o command= -p "$p" 2>/dev/null || true)"
    [ -n "$cmd" ] || continue
    case "$cmd" in
      *chrome-native-host*)       continue ;;  # started by Chrome, holds no Claude data
      *chrome_crashpad_handler*)  continue ;;  # crash reporter
    esac
    LIVE=$((LIVE+1))
  done
  [ "${LIVE}" -eq 0 ] || die "Claude Desktop is still running (${LIVE} processes). Quit it with ⌘Q and retry."
fi
echo "OK Claude is not running"

# ------------------------------------------------------------- backup
if [ -f "$ROOT/.backup-done" ]; then
  BK="$(cat "$ROOT/.backup-done")"
  echo "--- backup: reusing ${BK}"
else
  BK="$ROOT/backup-$STAMP"; mkdir -p "$BK"
  echo "--- backup (APFS clone) -> ${BK}"
  cp -Rpc "$APP_NEW" "$BK/app-data" 2>"$BK/.err1" || true
  cp -Rpc "$HOME/.claude" "$BK/dot-claude" 2>"$BK/.err2" || true
  FAIL=0
  for pair in "$APP_NEW|$BK/app-data" "$HOME/.claude|$BK/dot-claude"; do
    a="$(find "${pair%%|*}" 2>/dev/null | wc -l | tr -d ' ')"
    b="$(find "${pair##*|}" 2>/dev/null | wc -l | tr -d ' ')"
    echo "    ${pair%%|*}: source=$a backup=$b"
    [ "$a" = "$b" ] || FAIL=1
  done
  [ "${FAIL}" -eq 0 ] || die "backup file counts differ (source untouched, safe). Nothing was written."
  echo "$BK" > "$ROOT/.backup-done"
  echo "OK backup verified"
fi

# ------------------------------------------------------------- sessions
echo "--- sessions (mode=${MODE})"
touch "$MAN_S"
COPIED=0; SKIPPED=0; FAILED=0

if [ "${MODE}" = "test" ]; then
  # 20 most recent sessions that were NOT spawned by a routine (routine sessions only show up
  # after their task is imported, so they would make the test look like a failure).
  LIST="$(python3 - "${CODE_SRC}" <<'PY'
import json, os, glob, sys
d = sys.argv[1]; rows = []
for f in glob.glob(os.path.join(d, "local_*.json")):
    try:
        j = json.load(open(f))
    except Exception:
        continue
    if j.get("scheduledTaskId") or j.get("spawnedFrom") or j.get("agentDispatched"):
        continue
    t = j.get("lastActivityAt") or j.get("createdAt") or 0
    rows.append((t, os.path.basename(f)))
rows.sort(reverse=True)
for _, b in rows[:20]:
    print(b)
PY
)"
else
  LIST="$(find "${CODE_SRC}" -maxdepth 1 -name 'local_*.json' -exec basename {} \;)"
fi

for b in ${LIST}; do
  if [ -e "${CODE_DST}/${b}" ]; then SKIPPED=$((SKIPPED+1)); continue; fi
  if cp -p "${CODE_SRC}/${b}" "${CODE_DST}/${b}"; then
    echo "${CODE_DST}/${b}" >> "$MAN_S"; COPIED=$((COPIED+1))
  else
    FAILED=$((FAILED+1))
  fi
done
echo "    copied=${COPIED} skipped=${SKIPPED} failed=${FAILED}"
[ "${FAILED}" -eq 0 ] || die "some copies failed; do not continue"
echo "    target now $(cnt "${CODE_DST}") sessions; source still $(cnt "${CODE_SRC}")"
[ "$(cnt "${CODE_SRC}")" = "${SRC_N}" ] || die "source session count changed!"

if [ "${MODE}" = "test" ]; then
  cat <<EOF

Test copy done (${COPIED} sessions).
  1. Reopen Claude Desktop.
  2. Confirm the sessions appear in the sidebar and that opening one shows full history.
  3. If they do NOT appear, run: bash rollback.sh   — then stop and investigate.
  4. If they do, quit Claude and run: bash migrate.sh all
EOF
  exit 0
fi

# bring along archive/backlog state if present and not already there
for extra in archived-sessions.idx backlog; do
  if [ -e "${CODE_SRC}/${extra}" ] && [ ! -e "${CODE_DST}/${extra}" ]; then
    cp -Rp "${CODE_SRC}/${extra}" "${CODE_DST}/${extra}"
    echo "    carried over ${extra}"
  fi
done

# ------------------------------------------------------------- tasks
echo "--- scheduled tasks (imported DISABLED)"
cp -p "${TASK_DST}" "${TASK_DST}.pre-import-backup-${STAMP}"
cp -p "${TASK_SRC}" "$ROOT/source-tasks-${STAMP}.json"

set +e
python3 - "${TASK_SRC}" "${TASK_DST}" "$ROOT/source-enabled-tasks-${STAMP}.txt" <<'PY'
import json, sys, os, datetime
src, dst, report = sys.argv[1:4]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
d = json.load(open(src)); t = d["scheduledTasks"]
was = [x["id"] for x in t if x.get("enabled")]
for x in t:
    x["enabled"] = False
    x["lastScheduledFor"] = now
    x["missedRunScanFloor"] = now
d["recordedSkips"] = {}
tmp = dst + ".tmp"
json.dump(d, open(tmp, "w"), ensure_ascii=False, indent=2)
os.chmod(tmp, 0o600)
os.replace(tmp, dst)
v = json.load(open(dst))["scheduledTasks"]
print(f"    imported {len(v)} tasks, enabled={sum(1 for x in v if x.get('enabled'))} (must be 0)")
open(report, "w").write(
    "Tasks that were ENABLED in the source. Restore exactly this set, and only after the user "
    "confirms:\n" + "\n".join(was) + "\n")
sys.exit(0 if len(v) == len(t) and not any(x.get("enabled") for x in v) else 1)
PY
RC=$?
set -e
[ "${RC}" -eq 0 ] || die "task import verification failed. Roll back with: bash rollback.sh"
echo "    enabled-task list saved to source-enabled-tasks-${STAMP}.txt — restore exactly this set."

# ------------------------------------------------------------- cowork
if [ "${MIGRATE_COWORK:-0}" = "1" ]; then
  echo "--- Cowork"
  touch "$MAN_C"; n=0
  CL="$(find "${COW_SRC}" -maxdepth 1 -name 'local_*.json' -exec basename {} \;)"
  for b in ${CL}; do
    stem="${b%.json}"
    [ -f "${COW_DST}/${b}" ] && continue
    cp -c "${COW_SRC}/${b}" "${COW_DST}/${b}" 2>/dev/null || cp "${COW_SRC}/${b}" "${COW_DST}/${b}"
    if [ -d "${COW_SRC}/${stem}" ] && [ ! -d "${COW_DST}/${stem}" ]; then
      cp -Rc "${COW_SRC}/${stem}" "${COW_DST}/${stem}" 2>/dev/null || cp -R "${COW_SRC}/${stem}" "${COW_DST}/${stem}"
    fi
    echo "${COW_DST}/${b}" >> "$MAN_C"; echo "${COW_DST}/${stem}" >> "$MAN_C"
    n=$((n+1))
  done
  for e in spaces spaces.json; do
    if [ -e "${COW_SRC}/${e}" ] && [ ! -e "${COW_DST}/${e}" ]; then
      cp -Rc "${COW_SRC}/${e}" "${COW_DST}/${e}" 2>/dev/null || cp -R "${COW_SRC}/${e}" "${COW_DST}/${e}"
      echo "${COW_DST}/${e}" >> "$MAN_C"
    fi
  done
  echo "    copied ${n} Cowork sessions"
fi

echo
echo "=== done. Reopen Claude Desktop and verify in the UI:"
echo "    - sessions visible; a transcript opens with full history"
echo "    - routines listed, and enabled/disabled matches the source"
echo "    - Cowork chats present"
echo
echo "    Then restore the enabled set — IN BATCHES:"
echo "      bash \"$HERE/restore-enabled.sh\" --dry-run"
echo "      bash \"$HERE/restore-enabled.sh\" --limit 5"
echo "      bash \"$HERE/restore-enabled.sh\""
echo "    Full checklist: docs/05-verification.md"
