# 04 — Pitfalls

Every item here cost real debugging time. Read it before you migrate.

## Data & safety

### The App must be fully quit before you touch its data

The app holds scheduling state in memory and writes it back on exit. Modifying
`scheduled-tasks.json` while it runs means your changes get overwritten. ⌘Q is not always enough —
check for a menu-bar process. A guard that greps for `Claude.app` processes will produce **false
positives** on macOS: `chrome-native-host` lives inside `Claude.app` but is started by Chrome and
does not touch session data. Exclude it (and `chrome_crashpad_handler`), or the guard will block
forever.

### Copy, never move

If the migration only ever copies, then rollback is always available and a mistake can never lose
data. This is worth more than any clever optimisation.

### Verify the backup

A backup whose file count you did not check is not a backup. Compare source and backup file counts
and abort if they differ. Use APFS clones (`cp -c` on macOS) so a 20 GB backup costs seconds and
almost no extra disk.

### Do not overwrite the archive index

`archived-sessions.idx` looks like state you should copy. It is not — the App **rebuilds it** from
each session's `isArchived` flag. Copying an older one over a newer one can only hurt.

## Scheduled tasks — the dangerous part

### Missed-run catch-up will fire your tasks at restore

Claude Desktop catches up on windows it "missed" while a task was disabled. If you import 50
enabled tasks whose `lastScheduledFor` is a week old, restoring can fire a week of publishing,
posting and outreach in one burst. **Irreversible**, and it will exhaust API quota.

Always: import with `enabled = false` **and** stamp `lastScheduledFor` and `missedRunScanFloor` to
the import time.

### Never decide for yourself which tasks should be enabled

The authoritative list is the **source** partition's `scheduledTasks[].enabled`, read *before* the
import forces everything to `false`.

Do not sort tasks by name and enable them in "sensible" batches. A task name tells you what a task
*does*; it does not tell you whether it *should run*. Tasks get paused for business reasons — a
frozen site, a banned social account, a page marked as not-to-be-promoted, a quality debt, a
pending re-evaluation. Enabling them "because they look harmless" is how you republish to a site you
were told to leave alone.

Restore exactly the set that was enabled, and only after the user confirms.

### Do not assume a task's model field is valid on the new deployment

Third-party deployments may expose a different model catalog. Check that the model ids referenced in
`scheduled-tasks.json` exist; a task with an unknown model may fail at run time.

## Sessions

### "Most of my sessions didn't migrate" — probably not

Two categories never appear in the sidebar folder list:

- **archived** sessions (hidden by design; visible only in the archive),
- **routine-spawned** sessions (they appear under **Routines**, and only after their routine is
  imported).

In a heavily automated setup, the large majority of sessions are routine-spawned. If you copied
2,000 and 150 show up, that is expected. Explain this **before** the user panics — it is the single
most common false alarm.

### Routine sessions need their task imported first

A session with a `scheduledTaskId` has nowhere to hang until that task exists. Import tasks and they
appear. If you are doing a partial test copy, pick **non-routine** sessions, or the test will look
like a failure.

### Cowork lives in a separate partition with different names

The Cowork partition (`local-agent-mode-sessions/`) is a different tree from the Code partition. In
3p mode its account and org directory names are **truncated** (8 characters) while the Code
partition uses the full UUIDs. Always `ls` the target directory rather than constructing the path.

### A test copy proves the mechanism

Whether the App accepts foreign session files cannot be proven from disk. Copy ~20 files first,
reopen the App, and look. It costs nothing and de-risks the whole migration.

## Accounts, plans and capabilities

### File presence is not capability

Pairing, OAuth, and published resources are **service-side relationships**, not files. Copying a
config that references a paired Chrome extension does not re-pair it. Verify capability by *using*
it, not by checking that a config key exists.

### The official Chrome extension needs a paid plan

After an account change it shows *"Claude in Chrome requires a paid plan"*, and no amount of local
configuration fixes that. Use a bridge instead — see [docs/03](03-browser-bridge.md).

### Plugins are account-synced

Marketplace plugins cannot be migrated by copying files; the manifest is refreshed from the server.
Reinstall them from the marketplace.

### Genuinely unrecoverable

Published Artifacts and claude.ai web chats are tied to the old account. Say so plainly instead of
letting the user keep hoping.

## Environment

### A "system proxy" does not reach command-line tools

If the machine uses a proxy app (Clash, Surge, …) in **system proxy** mode, only applications that
honour the system proxy setting use it — typically just browsers. `curl`, `python`, `wget` and
anything else started from a shell connect **directly** and therefore fail or time out for blocked
hosts.

Symptom: the browser opens Google fine, but every script that talks to Google times out — and it
looks intermittent, because it depends on whether the shell happened to have a proxy variable set.
In one migration this made an entire SEO automation suite report `TimeoutError` on 13/13 hosts while
the browser channel worked perfectly.

**Fix:** export the proxy for shells. Put it in `~/.zshenv` so non-interactive shells (which is what
scheduled tasks use) get it too:

```sh
# ~/.zshenv — only when the proxy port is actually listening, so a stopped proxy
# does not silently point every tool at a dead endpoint
if nc -z -G 1 127.0.0.1 7933 >/dev/null 2>&1; then
  export HTTP_PROXY="http://127.0.0.1:7933"
  export HTTPS_PROXY="http://127.0.0.1:7933"
  export http_proxy="http://127.0.0.1:7933"
  export https_proxy="http://127.0.0.1:7933"
  export NO_PROXY="localhost,127.0.0.1,::1,*.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
  export no_proxy="$NO_PROXY"
fi
```

Verify from a fresh non-interactive shell, not the one you are sitting in:

```bash
zsh -c 'echo $HTTPS_PROXY; curl -s -o /dev/null -w "%{http_code}\n" https://www.google.com'
```

Child processes inherit it, so `bash script.sh` and `python3 script.py` are covered too.

The alternative is to switch the proxy app to **TUN mode**, which routes all traffic at the network
layer and needs no environment variables — at the cost of taking over the whole machine's routing.

## Shell-script landmines

These are not specific to migration, but they are exactly the kind of bug that makes a migration
script fail silently.

### `set -euo pipefail` + `cmd | head` = silent abort

With `pipefail`, `ls -t ... | head -10` fails with SIGPIPE (exit 141) as soon as `ls` writes more
than `head` reads, and `set -e` then aborts the whole script **without printing anything**. Use
`find … | sed -n '1,10p'`, or take the whole list and slice it in the language of your choice.

### `$VAR` followed by a non-ASCII character

In a UTF-8 locale, bash treats a following non-ASCII character as part of the variable name. A
Chinese or accented character right after `$VAR` makes bash look for a variable that does not
exist, and under `set -u` the script dies. Always write `${VAR}`. This reproduces only in some
locales, so a CI sandbox running under `LC_ALL=C` will not catch it.

### Empty glob → `"0\n0"`

`ls dir/*.json 2>/dev/null | wc -l || echo 0` outputs `0` **and** `0` when the directory is empty,
because `wc` already succeeded. Use `find dir -maxdepth 1 -name '*.json' | wc -l`.

### A "check passed" that actually checked nothing

A health check that parses files with a regex tuned to one format will silently skip files in
another format — and a skipped object looks identical to a passing one. Always print
"expected N / checked M / skipped K", and treat "skipped" as **not checked**, never as "passed".

## Reporting

Report each item as **passed / failed / not checked**. "The files are there" is not "it works". A
config check is not a connection check. A local build is not a deployment.

---

## Fixed 2026-10-16 (a separate audit found these)

These were real, and they are documented here because the fixes change behaviour you may be
relying on. The same five were found in the sibling kit and fixed in both.

### A reused backup was not always a backup

`.backup-done` stored an absolute path and nothing re-checked it. Delete `backup-*` to free space
— a normal thing to do between `test` and `all` — or move the repo, and the next run printed
`reusing <a path that no longer exists>` and then wrote into a live partition **with no backup at
all**, exiting 0. It now checks the directory exists and still has `app-data` and `dot-claude`.

### "Claude is still running" when it was not

The guard matched the **full command line**, so it counted Squirrel's auto-updater
(`.../Squirrel.framework/Resources/ShipIt`), which is inside the bundle and can outlive a ⌘Q, and
any process whose *arguments* merely mentioned `Applications/Claude.app` — a shell running
`ps aux | grep Applications/Claude.app` matched itself. It now matches the executable path
(`ps -o comm=`) and names ShipIt explicitly. See `scripts/lib-appguard.sh`.

### Same-named sessions were skipped silently

If the target already had a `local_*.json` with the same name, the copy was skipped and the only
trace was a number in `skipped=N`. When the source's copy is the newer one, that silently discards
the newer state. Now each same-named file is resolved on its own: identical → left alone; source
newer → replaced, with the target's copy parked in `replaced-sessions/<stamp>/`; target newer or
unparseable → the target's copy is kept and written to `conflicts-<stamp>.txt`.

### Rollback could delete things it did not create

The session loop had a "changed since the migration" guard; the Cowork loop did not, and
`migrate.sh` recorded a Cowork workspace directory in the manifest even when it had just decided
not to copy it. Rollback could therefore delete a directory it had never touched. Rollback now
requires the source twin to exist and match before deleting anything, and only directories that
were actually copied are recorded.

### `archived-sessions.idx` / `backlog` were copied but not tracked

They were copied into the target and never written to a manifest, so `rollback.sh` could not undo
the copy — it only recognised `local_*.json`. They are now recorded, and rollback accepts them.

### If the target had no `scheduled-tasks.json`, rollback did not undo the import

`migrate.sh` writes a `.pre-import-backup-*` only when there is a file to back up; with none,
`rollback.sh` found nothing and skipped the whole task section, leaving the imported file behind.
`migrate.sh` now leaves a `.tasks-created-by-restore` marker and rollback deletes the file it
created.
