# 01 — How Claude Desktop stores your data (and why it looks gone)

Understanding this table is 90% of the migration.

## The two layers

Claude Desktop keeps state in two very different kinds of place.

### Layer 1 — content that is **not** account-scoped

| What | Path |
|---|---|
| Conversation transcripts (the real, full content) | `~/.claude/projects/<path-encoded>/<sessionId>.jsonl` |
| Global rules | `~/.claude/CLAUDE.md` |
| Memory | `~/.claude/projects/<path-encoded>/memory/` |
| Skills | `~/.claude/skills/` |
| Scheduled-task **instructions** | `~/.claude/scheduled-tasks/<taskId>/SKILL.md` |
| Settings, plugins cache, hooks | `~/.claude/` |
| Your project files | wherever you keep them |

Nothing here is tied to an account, an organization, or a deployment mode. Switching accounts does
**not** touch any of it. In practice this is the bulk of your work — often tens of gigabytes.

### Layer 2 — metadata that **is** account-scoped

```
~/Library/Application Support/Claude/
  claude-code-sessions/
    <accountUUID>/
      <orgUUID>/
        local_<uuid>.json        # one file per session: title, cwd, model, archived flag, ...
        scheduled-tasks.json     # all routines for this account
        archived-sessions.idx    # which session ids are archived (the App rebuilds this)
        backlog, deleted_*       # misc bookkeeping
  local-agent-mode-sessions/
    <accountUUID>/<orgUUID>/     # Cowork (the "Chat / Cowork" tab) — same shape
```

The App builds the sidebar by **scanning the folder for the account you are currently logged into**.
There is no database and no index file to update — which is exactly why copying files into the new
partition works.

## Why the sidebar is empty after switching

The App scans `claude-code-sessions/<currentAccountUUID>/<currentOrgUUID>/`. After switching, that
folder is brand new and empty, so the sidebar is empty — while Layer 1 is completely untouched.
Your transcripts are still there; the App just has no pointer to them.

## Third-party / gateway mode ("3p")

Claude Desktop can run in a third-party deployment mode. Tools like
[CC Switch](https://github.com/farion1231/cc-switch) configure this: the app talks to a local
gateway on `127.0.0.1` instead of logging into Anthropic, which lets you use a non-Anthropic
account or an API relay.

Two things change, and both are easy to miss:

1. **The whole app data directory moves.** The app launches with
   `--user-data-dir=~/Library/Application Support/Claude-3p`. So all of Layer 2 now lives under
   `Claude-3p/`, completely separate from the old `Claude/` directory.
2. **The account/org UUIDs are synthetic.** In 3p mode the account is a fixed placeholder and the
   organization is `00000000-0000-4000-8000-000000000001`. There is also a `.profile-origin.json`
   next to the partition that records `{"mode":"local","org":"…"}`.

### A trap specific to 3p: truncated directory names

In 3p mode the **Code** partition uses the full UUIDs, but the **Cowork** partition uses
**truncated** 8-character directory names:

```
Claude-3p/claude-code-sessions/<accountUUID>/00000000-0000-4000-8000-000000000001/
Claude-3p/local-agent-mode-sessions/<accountUUID-short>/00000000/
```

(3p mode uses a synthetic account UUID and the placeholder org
`00000000-0000-4000-8000-000000000001`.)

If you build the Cowork target path from the same UUIDs as the Code path, it will not exist. Read
the real directory names with `ls` instead of constructing them.

## What the session metadata JSON contains

A `local_<uuid>.json` is a flat object. The important fields:

| Field | Meaning |
|---|---|
| `sessionId` | the `local_*` id |
| `cliSessionId` | points at the transcript in `~/.claude/projects/` |
| `cwd`, `originCwd` | used to group the session under a folder in the sidebar |
| `title`, `titleSource` | sidebar label |
| `model`, `effort`, `permissionMode` | per-session settings |
| `isArchived` | archived sessions are hidden from the normal list |
| `scheduledTaskId` | if present, this session was spawned by a routine — it does **not** appear under a
folder; it appears under **Routines**, and only after that routine has been imported |
| `importedUnconfirmed` | if present, the App hides the session from folder grouping |

Crucially, **there are no account or organization fields**. That is why copying the file across
accounts is safe and why the App accepts it.

## Other things that look lost but aren't

- **Archived sessions** — hidden by design. `archived-sessions.idx` lists them, and the App
  **rebuilds that file itself** from each session's `isArchived` flag, so you do not need to copy
  it (and should not overwrite a newer one).
- **Routine-spawned sessions** — they only appear once their routine exists. Import tasks and they
  show up.
- **Plugins** — synced from the marketplace per account. Copying files does not work; reinstall.
- **Artifacts and claude.ai web chats** — genuinely tied to the old account. Unrecoverable.

## Platform notes

Paths above are macOS. On Linux the app data directory is typically
`~/.config/Claude/`; on Windows `%APPDATA%\Claude\`. The two-layer structure is the same; verify
the exact locations with `ls` before trusting any path.
