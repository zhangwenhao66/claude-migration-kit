# 05 — Verification checklist

Migration scripts finishing is not migration succeeding. This is how you actually know.

## The one rule

Report every item as **passed / failed / not checked**. Three states, no collapsing:

- "the files are present" is not "it works",
- "the config says X" is not "the connection does X",
- "I could not check" is **not** passed.

A local build is not a deployment. A config check is not a connection check. Files on disk are not
capability.

---

## 1. Sessions

| Check | How | Pass looks like |
|---|---|---|
| Sidebar shows sessions | reopen Claude Desktop | the ones you copied are listed |
| Transcript is complete | open one, scroll to the top | full history, not a stub |
| You can continue it | send a message in an old session | it answers in context |

**Expect fewer entries than you copied.** Archived sessions are hidden by design; routine-spawned
sessions only appear under **Routines**, and only after their task is imported. If you copied 2,000
and see 150, that is usually correct — check the arithmetic before assuming failure:

```bash
# count the SOURCE partition by category (before migrating)
python3 - "$CODE_SRC" <<'PY'
import json, glob, os, sys
routine = archived = plain = 0
for f in glob.glob(os.path.join(sys.argv[1], "local_*.json")):
    j = json.load(open(f))
    if j.get("scheduledTaskId") or j.get("spawnedFrom") or j.get("agentDispatched"):
        routine += 1
    elif j.get("isArchived"):
        archived += 1
    else:
        plain += 1
print(f"routine-spawned={routine}  archived={archived}  plain(visible in folders)={plain}")
PY
```

Only the **plain** count should show up in the sidebar folders.

## 2. Routines

| Check | How | Pass looks like |
|---|---|---|
| Tasks exist | Routines list | the expected count |
| **Enabled/disabled matches the source** | compare against the list you saved in step 0 | same set, no extras |
| A task can actually run | trigger one low-risk task manually | it completes and writes its log |

The middle row is the one people skip, and the one that matters. If you enabled a task that was
paused in the source, you may have republished to a site you were told to leave alone. Check it.

## 3. Cowork

Reopen the Cowork/Chat tab: chats listed, opening one shows history, workspaces present.

## 4. Browser automation — including the focus check

Functional check first:

> Ask Claude: *use the browser tools to open `https://example.com` and read me its title.*

Then the check that nobody thinks of:

| Check | How | Pass looks like |
|---|---|---|
| Navigation works | the call returns the page title | non-empty title |
| **The user's focus was not stolen** | watch the Chrome window while it runs | their active tab does not change |
| Clicking works | fill a form and click a button | the page reacts |
| No windows pile up | count Chrome windows before/after | unchanged |

### Verify what actually ran, not what is configured

This is the trap that cost us the most time. A config can look perfect while the agent calls a
**different** tool that bypasses every default you set.

```bash
# find a recent session transcript, then count which tools it really called
grep -oE 'mcp__[a-zA-Z0-9_-]+__[a-zA-Z0-9_]+' <session>.jsonl | sort | uniq -c | sort -rn | head
```

Every browser call must be under the wrapper's server name. If you see the raw server name, the
defaults are not being applied, no matter what the config says. (See
[docs/03 §6](03-browser-bridge.md).)

### Then verify the defaults themselves

Run the sequence on a **background** tab — navigate, read, find, fill, click, screenshot, scroll,
JS, read text — and confirm the user's active tab never changes. That is the whole test:

```bash
# get the active tab id
#  → run the browser steps
# get the active tab id again
#  → the two ids must be identical
```

If they differ, something is activating a tab. The usual suspects, in order:

1. the raw MCP server is registered alongside the wrapper (see above),
2. `background: true` is not being passed,
3. `chrome_switch_tab` was called — which is *correct* only when the user needs to look at a page,
   and a bug otherwise.

## 5. Things you cannot verify, and should say so

- plugins (reinstall, then check the Skills list),
- published Artifacts and claude.ai web chats (unrecoverable),
- any task that has not run yet — its *existence* is verified, its *behaviour* is not.

Say "not yet run" rather than implying it works.

---

## Copy-paste checklist

```
[ ] sessions visible in the sidebar
[ ] opened one: full history, can continue
[ ] count matches expectation (non-archived, non-routine)
[ ] routines listed
[ ] enabled/disabled == source list  ← do not skip
[ ] one task manually triggered and completed
[ ] Cowork chats + workspaces present
[ ] browser: navigate + read works
[ ] browser: user's active tab unchanged (focus not stolen)
[ ] browser: task transcripts show only the wrapper's server name
[ ] no extra Chrome windows created
[ ] plugins reinstalled
[ ] old partition + backup kept (rollback available)
```
