---
name: EPIC
about: A coordinating issue for a larger body of work spanning multiple sub-issues.
title: 'EPIC: <capability or outcome>'
---

<!--
Follow the fspec Issue Authoring Guide: https://github.com/jvrck-labs/fspec/blob/main/docs/ISSUE_AUTHORING_GUIDE.md
The test: a fresh agent can do this issue with no questions. One unit of work per issue.
Base Current State and Files on `main` (index.html, scripts/, .github/workflows/, data/): name the commit, functions, element ids and line numbers you checked.
Verification must be runnable bash: jq/grep/curl on the repo, a local `python3 -m http.server` plus headless Chrome `--dump-dom`, or the live site.
-->
EPICs organise execution. They are not vague buckets.

## Summary
<2-5 sentences: end-state capability, why it matters>

## Goal
After this EPIC is complete:
1. ...
2. ...

## Execution Plan / Phases
### Phase 1: <name>
- #... <sub-issue>

### Phase 2: <name>
- #...

## Dependency Graph
```
#A ──► #B ──► #D
        │
        └──► #C ──► #D
```

## Sub-Issues
- [ ] #... — <one-line description>
- [ ] #... — <one-line description>

## Cross-Repo Implications
<other repos affected, or `None`>

## Constraints / Non-Goals
- No new libraries, CDN `<script src>`/`<link>` or build tooling without an owner decision.
- Never hand-edit `data/`. The data bot commits right after every merge to `main` (`git add .`), so rebase before merge.
- Keep table column indices 0–10. Append any new CSV column **last** and keep it off the table unless the issue says otherwise.
- Existing URL params and shared links must behave as on `main`.

## Success Criteria (EPIC level)
- [ ] All sub-issues closed
- [ ] End-state capability demonstrably works: <how>
