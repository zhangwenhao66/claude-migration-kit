#!/usr/bin/env bash
# Shared app guard, sourced by restore.sh / rollback.sh / restore-enabled.sh.
#
#   claude_app_pids     -> prints the PIDs of the Claude Desktop app itself, one per line
#
# Why this is a shared file rather than three copies: they had drifted. Two used
# `ps -o command=` and one used `ps -o command=` without the empty-string guard, and all three
# matched on the *full command line*. That makes `pgrep -f "Applications/Claude.app"` produce
# two kinds of false positive:
#
#   * Squirrel's auto-updater, /Applications/Claude.app/Contents/Frameworks/Squirrel.framework/
#     Resources/ShipIt — it is part of the bundle, it can outlive a ⌘Q, and it holds none of the
#     app's scheduling state;
#   * anything whose *arguments* merely contain that path — a shell running
#     `ps aux | grep Applications/Claude.app`, for instance, matches itself.
#
# Matching the executable path (`ps -o comm=`) instead of the command line removes the second
# class entirely and lets us name the first precisely.

claude_app_pids() {
  local p exe
  for p in $(pgrep -f "Applications/Claude.app" 2>/dev/null || true); do
    exe="$(ps -o comm= -p "$p" 2>/dev/null || true)"
    [ -n "${exe}" ] || continue
    # Only processes whose executable actually lives inside the bundle.
    case "${exe}" in
      /Applications/Claude.app/*|"$HOME"/Applications/Claude.app/*) ;;
      *) continue ;;
    esac
    # Helpers that are not the app and hold none of its scheduling state.
    case "${exe}" in
      *chrome-native-host*)        continue ;;   # started by Chrome
      *chrome_crashpad_handler*)   continue ;;   # crash reporter
      *Squirrel.framework*|*ShipIt*) continue ;; # auto-updater
    esac
    printf '%s\n' "${p}"
  done
}
