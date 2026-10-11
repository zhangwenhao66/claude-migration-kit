# claude-migration-kit

**Keep your entire Claude Code setup when your Claude account dies.**

If your Anthropic account gets banned, suspended, or you simply stop paying, Claude Desktop
opens up with an empty sidebar: no sessions, no routines, no memory. It looks like everything
is gone.

It isn't. Your transcripts, scheduled tasks, skills, memory and project files are all still on
disk. Claude Desktop just reads a different folder per account.

This kit is a **skill + scripts** that move everything from the old account into a new one —
including a third-party gateway account (e.g. via [CC Switch](https://github.com/farion1231/cc-switch))
— so you can keep working in the exact same environment: same sessions, same routines, same
skills, same memory, same browser automation.

> Built and battle-tested on macOS. The ideas are platform-independent; paths differ on
> Linux/Windows (see [docs/01-data-layout.md](docs/01-data-layout.md)).

---

## The core insight

Claude Desktop stores its state in two very different places:

| Layer | Location | Scoped by account? |
|---|---|---|
| **Conversation transcripts** (the real content) | `~/.claude/projects/<path-encoded>/<sessionId>.jsonl` | **No** — only by working directory |
| **Session list metadata** (titles, pointers) | `~/Library/Application Support/Claude/claude-code-sessions/<accountUUID>/<orgUUID>/` | **Yes** |
| **Rules / memory / skills / task instructions** | `~/.claude/` | **No** |
| **Project files** | wherever you keep them | **No** |

So when you switch accounts, the App scans an empty `<newAccountUUID>/<newOrgUUID>/` folder and
shows nothing — while gigabytes of transcripts sit untouched in `~/.claude/projects/`.

**Copy the metadata files into the new account's folder and everything is back.** No database to
patch, no export/import format — the session metadata JSON contains no account fields at all.

A second key fact: Claude Desktop supports a **third-party deployment mode** (`"deploymentMode": "3p"`)
that routes model traffic through a local gateway instead of Anthropic's login. Tools like
CC Switch drive this. In 3p mode the app uses a **separate data directory** (`Claude-3p`), which is
why nothing shows up there either — same fix applies.

---

## What this kit gives you

- **`SKILL.md`** — a Claude Code skill you drop into `~/.claude/skills/`. Once installed, you can
  just ask Claude *"migrate my old Claude account into this one"* and it walks the whole thing.
- **`scripts/migrate.sh`** — backup → copy sessions → import scheduled tasks (all paused) → copy
  Cowork. Copy-only, never moves, never deletes; the old account is left byte-for-byte intact.
- **`scripts/rollback.sh`** — precise, manifest-based undo. Only deletes files it copied.
- **`docs/`** — how the storage works, step-by-step migration, the browser-access problem, and a
  full pitfalls list.

---

## Quick start

```bash
git clone <this repo>
cd claude-migration-kit

# 1. Find your partitions
bash scripts/find-partitions.sh

# 2. Edit config with the source/target UUIDs it prints
cp scripts/config.example.sh scripts/config.sh
$EDITOR scripts/config.sh

# 3. Read-only preflight (safe while Claude is running)
bash scripts/migrate.sh check

# 4. Quit Claude Desktop completely (⌘Q), then:
bash scripts/migrate.sh test    # move the 20 most recent sessions only, verify, then:
bash scripts/migrate.sh all     # everything + scheduled tasks (imported paused) + Cowork
```

Then reopen Claude. Details and verification steps: [docs/02-migration.md](docs/02-migration.md).

Browser automation after migration is a separate, important chapter:
[docs/03-browser-bridge.md](docs/03-browser-bridge.md).

---

## What is preserved

| Asset | Preserved? | Notes |
|---|---|---|
| Conversation transcripts | ✅ | Already shared; the App just needs the metadata |
| Session list (titles, folders) | ✅ | Copy `local_*.json` into the new partition |
| Scheduled tasks / routines | ✅ | Imported **paused**, so nothing fires on restore |
| Skills (`~/.claude/skills/`) | ✅ | Not account-scoped — nothing to do |
| Memory (`~/.claude/projects/*/memory/`) | ✅ | Not account-scoped |
| `CLAUDE.md` / rules | ✅ | Not account-scoped |
| Project files & git | ✅ | Never touched |
| Cowork sessions + workspaces | ✅ | Separate partition, same technique |
| Browser automation | ⚠️ | Needs re-pairing; official extension needs a paid plan → see the bridge doc |
| Plugins | ❌ | Account-synced by the marketplace; reinstall them |
| Published Artifacts / claude.ai web chats | ❌ | Tied to the old account; unrecoverable |

---

## Requirements

- macOS (paths are macOS-specific; adapt for other OSes)
- `bash`, `python3`
- Claude Desktop
- For the browser bridge: Node.js ≥ 18 and Chrome

---

## License

MIT — see [LICENSE](LICENSE).
