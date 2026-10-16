#!/usr/bin/env bash
# Undo a migration.
#
#   1. put back any session file migrate.sh REPLACED (from replaced-sessions/<stamp>/)
#   2. delete exactly the files migrate.sh COPIED (from manifest-sessions.txt / manifest-cowork.txt)
#   3. restore scheduled-tasks.json from its pre-import backup — or delete it if the restore
#      created it because the account had none
#
# It never touches the source partition, and it will not delete anything that has changed since
# the restore, or that it cannot prove came from the source.
#
# Requires Claude Desktop to be quit.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"   # where migrate.sh wrote its manifests
if [ ! -f "$HERE/config.sh" ]; then
  echo "config.sh not found. Copy config.example.sh to config.sh and fill it in." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$HERE/config.sh"

die() { echo "ABORT: $*" >&2; exit 1; }

# shellcheck source=/dev/null
source "$HERE/lib-appguard.sh"
LIVE="$(claude_app_pids | wc -l | tr -d ' ')"
[ "${LIVE}" -eq 0 ] || die "Claude Desktop is still running. Quit it first (⌘Q)."

# ---------------------------------------------------------------- 1. replaced sessions
if [ -f "$ROOT/manifest-replaced.txt" ]; then
  n=0; skip=0
  while IFS="$(printf '\t')" read -r tgt bak; do
    [ -n "${tgt}" ] || continue
    case "$tgt" in
      "${CODE_DST}"/*) ;;
      *) echo "refusing (unexpected path): $tgt"; continue ;;
    esac
    if [ ! -f "${bak}" ]; then
      echo "keeping (backup missing): $tgt"; skip=$((skip+1)); continue
    fi
    cp -p "${bak}" "${tgt}" && n=$((n+1))
  done < "$ROOT/manifest-replaced.txt"
  echo "replaced sessions restored=${n} kept=${skip}"
fi

# ---------------------------------------------------------------- 2. task file
LATEST="$(find "${CODE_DST}" -maxdepth 1 -name 'scheduled-tasks.json.pre-import-backup-*' 2>/dev/null | sort | tail -1)"
if [ -n "${LATEST}" ]; then
  cp -p "${LATEST}" "${CODE_DST}/scheduled-tasks.json"
  echo "restored scheduled-tasks.json from $(basename "${LATEST}")"
elif [ -f "$ROOT/.tasks-created-by-restore" ] && [ -f "${CODE_DST}/scheduled-tasks.json" ]; then
  # The account had no task file before the migration; restoring means removing the one we made.
  rm -f "${CODE_DST}/scheduled-tasks.json"
  echo "removed scheduled-tasks.json (the account had none before the migration)"
fi

# ---------------------------------------------------------------- 3. copied sessions
del=0; keep=0
if [ -f "$ROOT/manifest-sessions.txt" ]; then
  # The manifest accumulates across runs (test then all), so de-duplicate before counting or
  # the same path is reported as deleted twice.
  sort -u "$ROOT/manifest-sessions.txt" > "$ROOT/.manifest-sessions.dedup"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # only delete paths we created, inside the target partition
    case "$p" in
      "${CODE_DST}"/local_*.json|"${CODE_DST}"/archived-sessions.idx|"${CODE_DST}"/backlog) ;;
      *) echo "refusing (unexpected path): $p"; continue ;;
    esac
    case "$p" in
      *"${SRC_ACC}"*) echo "refusing (source path): $p"; continue ;;
    esac
    tw="${CODE_SRC}/$(basename "$p")"
    # if it differs from the source, the user has used it since — keep it
    if [ -f "$p" ] && [ -f "$tw" ] && ! cmp -s "$p" "$tw"; then
      keep=$((keep+1)); continue
    fi
    [ -e "$p" ] && { rm -f "$p"; del=$((del+1)); }
  done < "$ROOT/.manifest-sessions.dedup"
fi
echo "sessions: deleted=${del} kept(used since)=${keep}"

# ---------------------------------------------------------------- 4. copied Cowork
if [ -f "$ROOT/manifest-cowork.txt" ]; then
  sort -u "$ROOT/manifest-cowork.txt" > "$ROOT/.manifest-cowork.dedup"
  cdel=0; ckeep=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      "${COW_DST}"/*) ;;
      *) echo "refusing (unexpected path): $p"; continue ;;
    esac
    # only treat it as a source path if we actually know the source dir name
    if [ -n "${SRC_ACC_COW:-}" ]; then
      case "$p" in
        *"${SRC_ACC_COW}"*) echo "refusing (source path): $p"; continue ;;
      esac
    fi
    tw="${COW_SRC}/$(basename "$p")"
    # The session loop above has always had a "changed since the migration" guard; this one did
    # not, so rollback would delete a Cowork file or workspace the user had since used — or one
    # that restore.sh never created at all. Require proof: the source twin must exist and match.
    if [ ! -e "${tw}" ]; then
      echo "keeping (no source twin — not created by this migration): $p"; ckeep=$((ckeep+1)); continue
    fi
    if [ -d "$p" ]; then
      if ! diff -rq "$p" "$tw" >/dev/null 2>&1; then
        echo "keeping (changed since the migration): $p"; ckeep=$((ckeep+1)); continue
      fi
    elif [ -f "$p" ] && ! cmp -s "$p" "$tw"; then
      echo "keeping (changed since the migration): $p"; ckeep=$((ckeep+1)); continue
    fi
    rm -rf "$p"; cdel=$((cdel+1))
  done < "$ROOT/.manifest-cowork.dedup"
  echo "cowork: deleted=${cdel} kept=${ckeep}"
fi

echo "source sessions: $(find "${CODE_SRC}" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')"
echo "target sessions: $(find "${CODE_DST}" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')"
