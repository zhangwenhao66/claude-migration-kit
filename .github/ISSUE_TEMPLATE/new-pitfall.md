---
name: A problem the docs don't cover
about: You hit something during a migration that this kit should warn about
title: "[pitfall] "
labels: ["documentation", "needs-triage"]
---

<!--
This is the most useful kind of report. A migration touches a lot of moving parts, and the
expensive failures are the ones nobody warned you about.
-->

## The problem

<!-- one or two sentences -->

## Why it is not obvious

<!-- What makes it hard to spot? Did it look like a different problem? Was it intermittent?
     Did a config look correct while the behaviour was wrong? -->

## How it showed up

<!-- the symptom, verbatim where possible -->

```
```

## The fix / workaround

<!-- what you did, and whether it is a permanent fix or a workaround -->

## Is this specific to a gateway ("3p") account, or does it apply to any account change?

<!-- This kit separates the two on purpose: docs/06 covers gateway-specific behaviour,
     and docs/04 lists things people wrongly attribute to the migration. -->

- [ ] gateway-specific
- [ ] applies to any account change
- [ ] unrelated to the migration (but hit during one)

## Checklist

- [ ] I removed account UUIDs, emails and personal paths from this report
- [ ] I checked it is not already in `docs/04-pitfalls.md` or `docs/06-gateway-mode.md`
