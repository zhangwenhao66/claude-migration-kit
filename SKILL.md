---
name: claude-account-migration
description: >
  Migrate a complete Claude Code environment from one Claude Desktop account (or deployment)
  to another — after an account is banned, suspended, or replaced by a third-party gateway
  (e.g. CC Switch, "3p" deployment mode). Restores sessions, scheduled tasks/routines, Cowork
  chats, and browser automation so the user can keep working exactly as before.

  Use this skill when the user says any of: "my Claude account got banned", "I switched
  accounts and everything is gone", "the sidebar is empty", "migrate my old Claude data",
  "I use a gateway / CC Switch now and can't see my sessions", "restore my routines",
  "my Chrome extension no longer works after switching accounts".
---

# Claude account migration

You are helping a user move their **entire** Claude Desktop environment from an old account (or
deployment) to a new one. The user's fear is "everything is gone". Usually **nothing is gone** —
the App is simply reading a different folder.

Read `docs/01-data-layout.md` first if you need the full picture. The short version:

- **Conversation transcripts** live in `~/.claude/projects/` and are **not** account-scoped.
- **Session list metadata** lives in
  `~/Library/Application Support/Claude/claude-code-sessions/<accountUUID>/<orgUUID>/` and **is**
  account-scoped. Copying `local_*.json` files into the new partition makes sessions reappear.
- **Skills, memory, `CLAUDE.md`** live in `~/.claude/` and are **not** account-scoped — there is
  nothing to migrate for them.
- **Scheduled tasks** live in `scheduled-tasks.json` inside the account partition.
- **Cowork** sessions live in a parallel partition with the same shape.
- In **third-party ("3p") / gateway** mode the whole app data directory is `Claude-3p`, not
  `Claude`, and the account/org UUIDs are synthetic.

## Rules you must follow

These mirror the safety design of the scripts in `scripts/`. Do not skip them.

1. **Copy only. Never move, never delete.** The source partition must stay byte-for-byte intact.
   This guarantees the user can always fall back.
2. **Back up first, and verify the backup** (file counts must match). A backup you did not verify
   is not a backup.
3. **Import scheduled tasks with `enabled = false`, and stamp `lastScheduledFor` /
   `missedRunScanFloor` to the import time.** Claude Desktop has a missed-run catch-up mechanism;
   without the stamp, enabling a task later can fire a burst of missed windows. Some of those tasks
   publish, post, or send email — that is irreversible.
4. **Never enable a task the user had disabled.** The authoritative "what was paused" list is the
   *source* partition's `scheduledTasks[].enabled`. A migration that forces everything to `false`
   destroys that information — read it **before** importing, and restore it deliberately, task by
   task, only after the user confirms.
5. **The App must be fully quit** before touching its data directory. The scripts check this and
   refuse to run otherwise.
6. **Never claim success from files being present.** Verify in the UI: sessions visible, a
   transcript opens with full history, routines listed, Cowork present.

## Procedure

### Step 0 — Reconnaissance (read-only, safe while Claude runs)

1. Identify the app data directory/directories in play:
   - `~/Library/Application Support/Claude/` (normal account mode)
   - `~/Library/Application Support/Claude-3p/` (third-party/gateway mode)
   Check which one the running app uses:
   `ps aux | grep -o -- '--user-data-dir=[^ ]*'`
2. Enumerate account partitions under each `claude-code-sessions/` and count `local_*.json` in
   each. The one with the most sessions is the **source**. The one the app currently reads (or the
   newest, near-empty one) is the **target**.
3. Do the same for `local-agent-mode-sessions/` (Cowork).
4. Read the source `scheduled-tasks.json` and **record which tasks are `enabled: true`** — you will
   need this later. Save it to a file; do not keep it only in context.
5. `bash scripts/find-partitions.sh` does 1–4 and prints ready-to-paste config values.

### Step 1 — Configure

Copy `scripts/config.example.sh` to `scripts/config.sh` and fill in the source/target
account+org UUIDs. Note: in 3p mode the **Cowork** partition uses **truncated** UUID directory
names (`1b032dcd/00000000`) while the Code partition uses the full UUIDs. The script reads both
from config; get them exactly right.

### Step 2 — Back up and migrate

```bash
bash scripts/migrate.sh check   # read-only preflight
# quit Claude Desktop completely (⌘Q), then:
bash scripts/migrate.sh test    # 20 most recent sessions, so the user can verify the mechanism
bash scripts/migrate.sh all     # remaining sessions + tasks (paused) + Cowork
```

`test` exists because "does the App accept foreign session files?" is the one assumption that
cannot be proven from disk. It costs nothing to check with 20 files.

After `test`, ask the user to reopen Claude and confirm sessions appear and a transcript opens.
Only then run `all`.

### Step 3 — Verify (do not skip)

Ask the user to confirm, in the UI:
- sessions appear in the sidebar (note: **archived** sessions and **routine-spawned** sessions
  legitimately do not appear in the folder list — explain this before they panic),
- opening one shows the full history,
- the Routines list shows the expected number of tasks,
- Cowork chats are back.

Then restore the enabled/disabled state **from the list you saved in step 0.4** — not from your own
guess about what "should" run.

### Step 4 — Browser automation

This is where most migrations silently break. Chrome extension pairing is **account-scoped**, so it
does not survive. And the official *Claude for Chrome* extension requires a **paid plan**, which a
gateway account usually cannot satisfy.

`docs/03-browser-bridge.md` documents a working, free alternative: the
[`mcp-chrome-bridge`](https://www.npmjs.com/package/mcp-chrome-bridge) extension + MCP server,
which drives the user's own Chrome (with their logins) and needs no Anthropic account. That doc
also lists the non-obvious fixes required to make it usable (single-instance bug, a hanging tool,
focus stealing, robot-detectable clicks, accidental new windows).

### Step 5 — Clean up

Tell the user:
- keep the old partition and the backup for a while — they are the rollback,
- plugins must be reinstalled from the marketplace (account-synced),
- Artifacts / claude.ai web chats are the only genuinely unrecoverable items.

## If something goes wrong

`bash scripts/rollback.sh` deletes exactly the files the migration copied (from its manifests) and
restores the task file. It never touches the source partition. Because the migration is copy-only,
rollback is always available.

## Reporting

Report per item as **passed / failed / not checked**. "Files are present" is not "it works". A
config check is not a connection check. Say what you actually verified and how.
