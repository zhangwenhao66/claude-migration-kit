#!/usr/bin/env bash
# Read-only reconnaissance: find Claude Desktop account partitions and report what is in them.
# Safe to run while Claude is open. Changes nothing.
set -uo pipefail

say() { printf '%s\n' "$*"; }

say "=== Claude Desktop data directories ==="
for d in "$HOME/Library/Application Support/Claude" "$HOME/Library/Application Support/Claude-3p"; do
  if [ -d "$d" ]; then
    say "  present: $d"
  else
    say "  absent : $d"
  fi
done

say
say "=== Which directory is the running app using? ==="
# Restrict to Claude.app, and cut everything from --user-data-dir= up to the next ' --' flag
# (the path contains spaces).
RUNNING="$(ps aux 2>/dev/null | grep 'Applications/Claude.app' | grep -v grep \
  | grep -o -- '--user-data-dir=.*' | head -1 | sed -E 's/--user-data-dir=//; s/ --.*//' || true)"
if [ -n "${RUNNING}" ]; then
  say "  ${RUNNING}"
else
  say "  (app not running, or not found)"
fi

count_sessions() { find "$1" -maxdepth 1 -name 'local_*.json' 2>/dev/null | wc -l | tr -d ' '; }

report_partitions() {
  local root="$1" label="$2"
  say
  say "=== $label: $root ==="
  [ -d "$root" ] || { say "  (missing)"; return; }
  local found=0
  for acc in "$root"/*/; do
    [ -d "$acc" ] || continue
    for org in "$acc"*/; do
      [ -d "$org" ] || continue
      found=1
      local n; n="$(count_sessions "$org")"
      say "  sessions=$n"
      say "    account: $(basename "$acc")"
      say "    org    : $(basename "$org")"
      local tj="$org/scheduled-tasks.json"
      if [ -f "$tj" ]; then
        python3 - "$tj" <<'PY' 2>/dev/null || say "    (could not parse scheduled-tasks.json)"
import json,sys
d=json.load(open(sys.argv[1]))
t=d.get("scheduledTasks",[])
en=[x["id"] for x in t if x.get("enabled")]
print(f"    tasks  : {len(t)} total, {len(en)} enabled")
if en:
    print("    enabled ids (SAVE THIS LIST):")
    for i in en: print("      -", i)
PY
      else
        say "    tasks  : (no scheduled-tasks.json)"
      fi
    done
  done
  [ "$found" -eq 1 ] || say "  (no partitions found)"
}

report_partitions "$HOME/Library/Application Support/Claude/claude-code-sessions" "Code sessions (Claude)"
report_partitions "$HOME/Library/Application Support/Claude-3p/claude-code-sessions" "Code sessions (Claude-3p)"
report_partitions "$HOME/Library/Application Support/Claude/local-agent-mode-sessions" "Cowork sessions (Claude)"
report_partitions "$HOME/Library/Application Support/Claude-3p/local-agent-mode-sessions" "Cowork sessions (Claude-3p)"

say
say "=== Next steps ==="
say "  1. The partition with the most sessions is your SOURCE."
say "     The one the running app uses (usually near-empty) is your TARGET."
say "  2. Save the enabled task ids printed above."
say "  3. cp scripts/config.example.sh scripts/config.sh and fill it in."
say "  4. bash scripts/migrate.sh check"
