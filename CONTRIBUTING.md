# Contributing

The most valuable contribution here is **a problem this kit doesn't warn about yet**.

## The one rule

**Every problem found during a migration gets written down, in the right document — including the
ones that turn out not to be the migration's fault.**

Migrations fail expensively in two ways:

1. something breaks and nobody warned you, and
2. something breaks, you blame the migration, and you "fix" the wrong thing.

So a finding goes in **one of two places**, and saying which is part of the fix:

| Finding | Goes in |
|---|---|
| Caused by switching to a **gateway ("3p")** account | `docs/06-gateway-mode.md` |
| Applies to **any** account change | `docs/04-pitfalls.md` |
| A symptom people **wrongly** attribute to the migration | `docs/04-pitfalls.md`, under "things that are NOT gateway problems" (in docs/06) |
| It changes **what you should check** | `docs/05-verification.md` |

If you are unsure which, file it and say so — deciding is part of the work.

## What makes a good entry

- **The symptom, verbatim.** The exact error text is what the next person will search for.
- **Why it is not obvious.** Intermittent? Did a config look correct while the behaviour was wrong?
  Did it look like a different problem? (Several entries here exist precisely because a check
  *looked* like it passed while it was actually checking nothing.)
- **The fix, and whether it is permanent.** If it needs re-applying after an upgrade, say so.
- **What you verified, and what you did not.** "Files are present" is not "it works".

## Adding a pitfall

1. Pick the document from the table above.
2. Match the existing shape: a heading that states the problem, then the symptom, then the fix.
3. If it is mechanical, add it to the verification checklist in `docs/05-verification.md` too —
   a pitfall nobody checks for will be hit again.
4. One focused commit. Explain the *symptom*, not just the change.

## Code

- `scripts/` is plain `bash`, macOS-oriented, `set -euo pipefail`.
- Copy-only, never move or delete anything in a user's data directory.
- Any script that writes into the app's data directory must refuse to run while Claude Desktop is
  running.
- Run `bash -n` on changed scripts before committing.

## Do not include

Account UUIDs, email addresses, gateway tokens, personal paths, or real site/task names. Redact
them in issues and in documentation examples alike.
