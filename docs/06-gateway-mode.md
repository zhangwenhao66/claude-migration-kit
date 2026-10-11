# 06 — What changes when you migrate to a gateway ("3p") account

Everything in docs/01–05 applies to any account change. This document covers what is **specific to
third-party / gateway deployments** — the mode you get from tools like
[CC Switch](https://github.com/farion1231/cc-switch), where Claude Desktop talks to a local gateway
instead of logging into Anthropic.

If you are migrating between two ordinary Anthropic accounts, you can skip this file. If your new
account is a gateway one, **read it before you declare the migration done** — several of these are
invisible until a task runs and fails.

## 1. The whole app data directory moves

The app launches with `--user-data-dir=~/Library/Application Support/Claude-3p`. Every partition
path from docs/01 is now under `Claude-3p/`, not `Claude/`.

Confirm which one is live rather than assuming:

```bash
ps aux | grep 'Applications/Claude.app' | grep -o -- '--user-data-dir=.*' | head -1
```

## 2. Account and organization UUIDs are synthetic

There is no real account, so the partition path uses a generated account UUID and the placeholder
organization `00000000-0000-4000-8000-000000000001`. The Cowork partition uses **truncated**
8-character directory names. Read the real names with `ls`; never construct them.

## 3. Server-side tools are provided by the gateway — and may not be enabled

This is the one that surprises people. `WebSearch` is not something Claude Code does locally; the
model asks the *API* to run a search. With a gateway in the middle, **the gateway has to implement
that capability**, and whether it is enabled is a setting on the gateway account — not on your
machine.

Symptom:

```
Failed to authenticate. API Error: 403 Access denied for web search.
Please go to the <your gateway> Console to verify the activation status.
```

What to expect:

- it can be **intermittent** — in our case an interactive session succeeded while a scheduled task
  on a different model route got 403 minutes earlier, so "it works when I try it" proves nothing
  about your tasks;
- it may be enabled **per model or per endpoint**, so some routes work and others do not;
- enabling it is a **gateway-console action** you may not be able to do from the machine.

**Mitigations**, in order of reliability:

1. enable the search capability in the gateway console, if your plan offers it;
2. have a second, independent search path (an API-based search provider) and make sure it has
   credit — do not assume it does;
3. fall back to driving a browser. This works, but it is slow and depends on the browser being up.

**Do not rely on a single search path.** In our migration the primary path returned 403 *and* the
backup was out of credit at the same time; the run only completed because it degraded all the way to
the browser.

## 4. The official browser extension is not usable

The Chrome extension that Claude Desktop normally drives requires a **paid Anthropic plan**, which a
gateway account generally cannot satisfy. Pairing is also account-scoped, so it does not survive the
switch regardless.

Use the free bridge described in [docs/03](03-browser-bridge.md). Budget real time for it — it needs
five fixes before it behaves.

## 5. The model catalog may differ

Tasks and settings that name a specific model id may reference something the gateway does not
expose. Check the ids your routines use against what the gateway offers before enabling them; a task
with an unknown model fails at run time, not at import time.

## 6. Rate limiting is now your gateway's, not Anthropic's

Third-party plans often have tighter concurrency. Expect `429 Too Many Requests` under load, and
enable routines in batches rather than all at once — a burst of tasks is exactly what triggers it.

## Things that are NOT gateway problems

Do not attribute these to the migration; they will follow you to any setup:

| Symptom | Real cause |
|---|---|
| scripts time out reaching Google, browser works | the machine's proxy is in **system proxy** mode, which command-line tools ignore — see [docs/04](04-pitfalls.md#a-system-proxy-does-not-reach-command-line-tools) |
| a search/API backup fails | that provider's own quota or credits, unrelated to the account switch |
| `git pull --rebase` conflicts in a repo with other work in progress | use a throwaway worktree instead of rebasing in place |

## Pre-flight checklist for a gateway migration

```
[ ] confirmed the live data directory is Claude-3p
[ ] read the real partition directory names with ls (do not construct them)
[ ] gateway web search: enabled? tested from a SCHEDULED TASK, not just interactively?
[ ] backup search path exists AND has credit
[ ] browser bridge installed, patched, and focus-safe
[ ] routine model ids verified against the gateway's catalog
[ ] routines enabled in batches, watching for 429
[ ] machine proxy exported for shells (docs/04) — even though it is not a gateway issue
```
