#!/usr/bin/env bash
# Undo a migration: delete exactly the files migrate.sh copied, and restore the task file.
# It never touches the source partition, and it will not delete a session you have since used.
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

if pgrep -f "Applications/Claude.app" >/dev/null 2>&1; then
  LIVE=0
  for p in $(pgrep -f "Applications/Claude.app" 2>/dev/null || true); do
    cmd="$(ps -o command= -p "$p" 2>/dev/null || true)"
    case "$cmd" in
      *chrome-native-host*|*chrome_crashpad_handler*) continue ;;
    esac
    LIVE=$((LIVE+1))
  done
  [ "${LIVE}" -eq 0 ] || die "Claude Desktop is still running. Quit it first."
fi

# restore the pre-import task file
LATEST="$(find "${CODE_DST}" -maxdepth 1 -name 'scheduled-tasks.json.pre-import-backup-*' 2>/dev/null | sort | tail -1)"
if [ -n "${LATEST}" ]; then
  cp -p "${LATEST}" "${CODE_DST}/scheduled-tasks.json"
  echo "restored scheduled-tasks.json from $(basename "${LATEST}")"
fi

del=0; keep=0
if [ -f "$ROOT/manifest-sessions.txt" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # only delete paths we created, inside the target partition
    case "$p" in
      "${CODE_DST}"/local_*.json) ;;
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
  done < "$ROOT/manifest-sessions.txt"
fi
echo "sessions: deleted=${del} kept(used since)=${keep}"

if [ -f "$ROOT/manifest-cowork.txt" ]; then
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
    [ -e "$p" ] && rm -rf "$p"
  done < "$ROOT/manifest-cowork.txt"
  echo "cowork cleaned"
fi

echo "source sessions: $(find "${CODE_SRC}" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')"
echo "target sessions: $(find "${CODE_DST}" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' ')"
