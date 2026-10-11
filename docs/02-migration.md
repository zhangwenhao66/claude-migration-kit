# 02 — Step-by-step migration

Follow this in order. Every step is reversible; nothing here deletes from the old account.

## Prerequisites

- Claude Desktop installed, and **opened at least once with the new account** so that its
  partition directory exists.
- `bash` and `python3` available.

---

## Step 0 — Find the partitions (read-only)

```bash
bash scripts/find-partitions.sh
```

It prints, for every app data directory it can find (`Claude/` and `Claude-3p/`):

- each `claude-code-sessions/<account>/<org>` partition and how many `local_*.json` it holds,
- the same for `local-agent-mode-sessions` (Cowork),
- how many tasks each partition's `scheduled-tasks.json` holds and **which are enabled**,
- which directory the currently running app uses.

Pick the **source** (usually the partition with the most sessions) and the **target** (the one the
running app uses — typically near-empty, containing only your current session).

Also note the source's **enabled task ids** — the script prints them. Save that list. You will need
it in step 3.

---

## Step 1 — Configure

```bash
cp scripts/config.example.sh scripts/config.sh
$EDITOR scripts/config.sh
```

Fill in the four UUID pairs (source/target × Code/Cowork). The script reads them from `config.sh`;
do not guess the Cowork ones — in 3p mode they are truncated (see
[docs/01](01-data-layout.md#a-trap-specific-to-3p-truncated-directory-names)).

---

## Step 2 — Back up and migrate

```bash
bash scripts/migrate.sh check
```

Read-only preflight: verifies the paths exist, counts sessions and tasks on both sides, checks free
disk space. Safe to run while Claude is open.

Then **quit Claude Desktop completely** (⌘Q; make sure the menu-bar icon is gone). The script
refuses to run if it detects the app.

```bash
bash scripts/migrate.sh test
```

This:
1. takes an APFS-cloned backup of the target app directory and `~/.claude` (fast, near-zero extra
   space) and verifies file counts,
2. copies the **20 most recently active, non-routine** sessions into the target partition.

Reopen Claude. **Verify before continuing:**

- do the sessions appear in the sidebar?
- does opening one show the **full** history?

Why only 20, and why non-routine: this is the one assumption that cannot be verified from disk —
whether the App accepts foreign session files. Twenty files cost nothing to test. Routine-spawned
sessions are excluded on purpose because they only appear after their routine is imported (step 3),
so they would look like a failure.

If they do not appear, run `bash scripts/rollback.sh` and open an issue — do not proceed.

```bash
# quit Claude again, then:
bash scripts/migrate.sh all
```

This copies the remaining sessions, imports `scheduled-tasks.json`, and copies Cowork.

---

## Step 3 — Importing scheduled tasks (the dangerous part)

The script imports every task with `enabled = false` and stamps `lastScheduledFor` and
`missedRunScanFloor` to the import timestamp.

**Why the stamp matters.** Claude Desktop catches up on "missed" windows. Without the stamp,
enabling a task later can immediately fire every window it "missed" while disabled. For a task that
publishes a blog post, posts to social media, or sends outreach email, that is **irreversible** —
and a burst of them can blow through your API quota in seconds. The stamp removes the missed
window entirely.

**Restoring the enabled state.** Now use the enabled-task list you saved in step 0.

**Do it in batches, not all at once.** Turning every task live in one go means a broken dependency
(an auth that did not survive, a browser bridge that is not connected, a quota that is exhausted)
shows up as many failed tasks at once, with no clean signal about which part broke. Staging makes
the failure legible.

```bash
# 1. See what would happen — writes nothing
bash scripts/restore-enabled.sh --dry-run

# 2. Enable a small first batch and let it run
bash scripts/restore-enabled.sh --limit 5

# 3. Watch one or two of those actually run (from the Routines list, or wait for their cron).
#    If they behave, enable more:
bash scripts/restore-enabled.sh --limit 20
bash scripts/restore-enabled.sh            # the rest
```

`--only a,b,c` enables exactly the ids you name, if you would rather pick the first batch yourself.

Two things this does **not** do, on purpose:

- it does not touch `lastScheduledFor` / `missedRunScanFloor`, so enabling a task later still cannot
  fire a backlog of missed windows;
- it does not rank tasks for you. `--limit N` takes the first N of the source list, which is
  neutral. **Do not** reorder by task name to put "safe-looking" tasks first — a task name says what
  a task does, not whether it is safe in *your* setup.

You can also toggle tasks by hand in the Routines list — but apply **the same set**:

- enable exactly the tasks that were `enabled: true` in the source,
- leave everything else disabled,
- **do not** decide for yourself which tasks "should" run. What was paused was paused for a reason
  (a frozen site, a banned account, a walled page, a quality debt). Task names do not tell you that.

The script also warns if any enabled task lacks a missed-run floor, and reports ids from the list
that do not exist in the new account (they were deleted, or never imported).

Restore in batches if you like, but restore *the same set*.

> In the Claude Desktop UI this is the Routines list. The migration copies
> `scheduled-tasks.json`; you can also toggle tasks one by one from the UI.

---

## Step 4 — Verify

In the UI, confirm all of:

| Check | Expected |
|---|---|
| Sessions in the sidebar | roughly the number of non-archived, non-routine sessions copied |
| Opening a session | full history, and you can continue the conversation |
| Routines list | the expected number of tasks, correct enabled/disabled state |
| Cowork tab | the chats are back, workspaces present |

Expect fewer sidebar entries than you copied. Two categories are hidden by design:

- **archived** sessions (visible only in the archive),
- **routine-spawned** sessions (visible under Routines).

If you copied 2,000 sessions and the sidebar shows 150, that is normal — most were routine-spawned.
Say so *before* the user concludes the migration failed.

---

## Step 5 — Browser automation

See [docs/03-browser-bridge.md](03-browser-bridge.md). Chrome extension pairing does not survive an
account change, and the official extension requires a paid plan. There is a free alternative.

---

## Rollback

```bash
bash scripts/rollback.sh
```

It reads the manifests written by `migrate.sh` and deletes exactly those files from the target, then
restores the pre-import `scheduled-tasks.json`. It will **not** delete a session you have since used
(it compares against the source before deleting). It never touches the source partition.

Because migration is copy-only, you can also simply delete the target partition and redo it.

---

## Timeline expectations

- Sessions: minutes (metadata is small; the transcripts were never moved).
- Scheduled tasks: seconds.
- Cowork: minutes to an hour depending on workspace size (it clones workspaces).
- Full UI verification: as long as it takes the user to click around. Do not skip it.
