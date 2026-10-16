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
# claude_app_pids() ignores the helpers that are not the app. See scripts/lib-appguard.sh for
# why matching the executable path matters: `ps -o command=` matched Squirrel's auto-updater and
# any process whose *arguments* merely contained the path.
# shellcheck source=/dev/null
source "$HERE/lib-appguard.sh"
LIVE="$(claude_app_pids | wc -l | tr -d ' ')"
[ "${LIVE}" -eq 0 ] || die "Claude Desktop is still running (${LIVE} process(es)). Quit it with ⌘Q and retry."
echo "OK Claude is not running"

# ------------------------------------------------------------- backup
# A reused backup is only a backup if it is still there. Deleting backup-* to free space, or
# moving the repo, otherwise left .backup-done pointing at a path that no longer existed, and the
# run wrote into a live partition with no backup at all while reporting success.
BK=""
if [ -f "$ROOT/.backup-done" ]; then
  CAND="$(cat "$ROOT/.backup-done" 2>/dev/null || true)"
  if [ -n "${CAND}" ] && [ -d "${CAND}/app-data" ] && [ -d "${CAND}/dot-claude" ]; then
    BK="${CAND}"
  else
    echo "--- backup: previous backup at '${CAND:-<empty>}' is gone or incomplete; making a new one"
    rm -f "$ROOT/.backup-done"
  fi
fi
if [ -n "${BK}" ]; then
  echo "--- backup: reusing ${BK}"
else
  BK="$ROOT/backup-$STAMP"; mkdir -p "$BK"
  echo "--- backup (APFS clone) -> ${BK}"
  # -c clones (instant, near-zero space) but only works on APFS; fall back to a real copy.
  cp -Rpc "$APP_NEW" "$BK/app-data" 2>"$BK/.err1" || cp -Rp "$APP_NEW" "$BK/app-data" 2>>"$BK/.err1" || true
  cp -Rpc "$HOME/.claude" "$BK/dot-claude" 2>"$BK/.err2" || cp -Rp "$HOME/.claude" "$BK/dot-claude" 2>>"$BK/.err2" || true
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

# Same-named files are the norm here, not an edge case: on the machine this kit was written on
# all 2847 target sessions also existed in the source. Most are byte-identical, but a third of
# the differing ones had a NEWER source — the session had been used on the gateway since the
# account last saw it. Skipping those silently threw away the newer state (completedTurns, model,
# lastAssistantUuid, publishedArtifacts, lastActivityAt). Decide per file, and never lose either
# copy: the target's version is parked in replaced-sessions/<stamp>/ before it is overwritten.
DEC_FILE="$ROOT/.decisions-$STAMP"
NAMES_FILE="$ROOT/.names-$STAMP"
REPL_DIR="$ROOT/replaced-sessions/$STAMP"
CONF_FILE="$ROOT/conflicts-$STAMP.txt"
MAN_R="$ROOT/manifest-replaced.txt"

# The name list goes through a file, not a pipe: `python3 - <<'PY'` already consumes stdin with
# the heredoc, so anything piped in would be silently dropped.
printf '%s\n' ${LIST} > "$NAMES_FILE"
python3 - "${CODE_SRC}" "${CODE_DST}" "$NAMES_FILE" > "$DEC_FILE" <<'PY'
import json, os, sys

src, dst, names_file = sys.argv[1], sys.argv[2], sys.argv[3]


def activity(path):
    try:
        with open(path, "rb") as fh:
            j = json.load(fh)
    except Exception:
        return None
    v = j.get("lastActivityAt") or j.get("createdAt")
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


for name in open(names_file, encoding="utf-8").read().splitlines():
    name = name.strip()
    if not name:
        continue
    a, b = os.path.join(src, name), os.path.join(dst, name)
    if not os.path.exists(b):
        print(f"{name}\tADD")
        continue
    try:
        if open(a, "rb").read() == open(b, "rb").read():
            print(f"{name}\tSAME")
            continue
    except OSError:
        print(f"{name}\tKEEP_UNREADABLE")
        continue
    ta, tb = activity(a), activity(b)
    if ta is None or tb is None:
        # Cannot tell which is newer -> do not guess. Keep the target's, report it.
        print(f"{name}\tKEEP_UNREADABLE")
    elif ta > tb:
        print(f"{name}\tREPLACE")
    else:
        print(f"{name}\tKEEP_TARGET_NEWER")
PY

COPIED=0; SKIPPED=0; FAILED=0; REPLACED=0; KEPT=0
while IFS="$(printf '\t')" read -r b decision; do
  [ -n "${b}" ] || continue
  case "${decision}" in
    ADD)
      if cp -p "${CODE_SRC}/${b}" "${CODE_DST}/${b}"; then
        echo "${CODE_DST}/${b}" >> "$MAN_S"; COPIED=$((COPIED+1))
      else
        FAILED=$((FAILED+1))
      fi
      ;;
    SAME)
      SKIPPED=$((SKIPPED+1))
      ;;
    REPLACE)
      mkdir -p "$REPL_DIR"
      if ! cp -p "${CODE_DST}/${b}" "${REPL_DIR}/${b}"; then FAILED=$((FAILED+1)); continue; fi
      printf '%s\t%s\n' "${CODE_DST}/${b}" "${REPL_DIR}/${b}" >> "$MAN_R"
      if cp -p "${CODE_SRC}/${b}" "${CODE_DST}/${b}"; then
        REPLACED=$((REPLACED+1))
      else
        FAILED=$((FAILED+1))
      fi
      ;;
    KEEP_TARGET_NEWER|KEEP_UNREADABLE)
      KEPT=$((KEPT+1)); echo "${CODE_DST}/${b}  (${decision})" >> "$CONF_FILE"
      ;;
    *)
      SKIPPED=$((SKIPPED+1))
      ;;
  esac
done < "$DEC_FILE"

echo "    copied=${COPIED} identical=${SKIPPED} replaced=${REPLACED} kept-target=${KEPT} failed=${FAILED}"
if [ "${REPLACED}" -gt 0 ]; then
  echo "    ${REPLACED} session(s) were UPDATED from the source; the target's older copy of each is"
  echo "    parked in replaced-sessions/${STAMP}/ and listed in manifest-replaced.txt."
fi
if [ "${KEPT}" -gt 0 ]; then
  echo "    ${KEPT} session(s) differ and the TARGET's copy was kept (it was newer, or the pair"
  echo "    could not be compared). Details: $(basename "$CONF_FILE")"
fi
[ "${FAILED}" -eq 0 ] || die "some copies failed; do not continue. Nothing else was written; sessions already copied can be undone with: bash rollback.sh"
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

# bring along archive/backlog state if present and not already there.
# Recorded in the manifest, or rollback cannot undo the copy.
for extra in archived-sessions.idx backlog; do
  [ -e "${CODE_SRC}/${extra}" ] || continue
  if [ ! -e "${CODE_DST}/${extra}" ]; then
    cp -Rp "${CODE_SRC}/${extra}" "${CODE_DST}/${extra}"
    echo "${CODE_DST}/${extra}" >> "$MAN_S"
    echo "    carried over ${extra}"
  elif ! diff -rq "${CODE_SRC}/${extra}" "${CODE_DST}/${extra}" >/dev/null 2>&1; then
    echo "    NOTE: ${extra} exists on both sides and differs; the target's copy was kept."
  fi
done

# ------------------------------------------------------------- tasks
echo "--- scheduled tasks (imported DISABLED)"
if [ -f "${TASK_DST}" ]; then
  cp -p "${TASK_DST}" "${TASK_DST}.pre-import-backup-${STAMP}"
else
  echo "    (no target scheduled-tasks.json to back up; a new one will be created)"
  echo "${TASK_DST}" > "$ROOT/.tasks-created-by-restore"
fi
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
    if [ -f "${COW_DST}/${b}" ]; then
      if ! cmp -s "${COW_SRC}/${b}" "${COW_DST}/${b}"; then
        echo "    NOTE: ${b} exists on both sides and differs; the target's copy was kept."
      fi
      continue
    fi
    cp -c "${COW_SRC}/${b}" "${COW_DST}/${b}" 2>/dev/null || cp "${COW_SRC}/${b}" "${COW_DST}/${b}"
    echo "${COW_DST}/${b}" >> "$MAN_C"
    # Only record the workspace directory if we actually created it. It used to be appended
    # unconditionally, even when the directory already existed, so rollback would delete a
    # directory the migration never touched.
    if [ -d "${COW_SRC}/${stem}" ]; then
      if [ ! -e "${COW_DST}/${stem}" ]; then
        cp -Rc "${COW_SRC}/${stem}" "${COW_DST}/${stem}" 2>/dev/null || cp -R "${COW_SRC}/${stem}" "${COW_DST}/${stem}"
        echo "${COW_DST}/${stem}" >> "$MAN_C"
      else
        echo "    NOTE: ${stem}/ exists on both sides; the target's workspace was kept (not merged)."
      fi
    fi
    n=$((n+1))
  done
  for e in spaces spaces.json; do
    [ -e "${COW_SRC}/${e}" ] || continue
    if [ ! -e "${COW_DST}/${e}" ]; then
      cp -Rc "${COW_SRC}/${e}" "${COW_DST}/${e}" 2>/dev/null || cp -R "${COW_SRC}/${e}" "${COW_DST}/${e}"
      echo "${COW_DST}/${e}" >> "$MAN_C"
    elif [ -f "${COW_SRC}/${e}" ] && ! cmp -s "${COW_SRC}/${e}" "${COW_DST}/${e}"; then
      echo "    NOTE: ${e} exists on both sides and differs; the source copy was NOT merged."
    elif [ -d "${COW_SRC}/${e}" ] && ! diff -rq "${COW_SRC}/${e}" "${COW_DST}/${e}" >/dev/null 2>&1; then
      echo "    NOTE: ${e}/ exists on both sides and differs; the source copy was NOT merged."
    fi
  done
  echo "    copied ${n} Cowork sessions"
  echo "    note: only local_* sessions and spaces/spaces.json are handled. Anything else in the"
  echo "          Cowork partition (memory/, usage-ledger/, workspace dirs, settings) is NOT copied."
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
