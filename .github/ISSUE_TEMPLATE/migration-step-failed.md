---
name: A step in the guide failed
about: You followed the docs and something did not work
title: "[step] "
labels: ["bug", "needs-triage"]
---

<!--
Before filing: the docs cover a lot of "this looks broken but is expected". Check
docs/05-verification.md (sessions hidden by design) and docs/04-pitfalls.md first.
Please redact your account/org UUIDs and any personal paths.
-->

## Which step

<!-- e.g. docs/02 step 3 — importing scheduled tasks -->

## What you expected

## What actually happened

<!-- paste the error verbatim; include the command you ran -->

```
```

## Environment

- OS and version:
- Claude Desktop version:
- Which deployment: ordinary account / gateway ("3p") — and which gateway tool
- Data directory in use (`ps aux | grep 'Applications/Claude.app' | grep -o -- '--user-data-dir=.*' | head -1`):

## What you already tried

## Checklist

- [ ] I read `docs/05-verification.md` and `docs/04-pitfalls.md` and this is not one of the
      "expected" behaviours described there
- [ ] I removed account UUIDs, emails and personal paths from this report
