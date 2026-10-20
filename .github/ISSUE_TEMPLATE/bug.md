---
name: Bug
about: Something is broken or behaving incorrectly.
title: 'fix: <action-oriented title>'
---

<!--
Follow the fspec Issue Authoring Guide: https://github.com/jvrck-labs/fspec/blob/main/docs/ISSUE_AUTHORING_GUIDE.md
The test: a fresh agent can do this issue with no questions. One unit of work per issue.
Base Current State and Files on `main` (index.html, scripts/, .github/workflows/, data/): name the commit, functions, element ids and line numbers you checked.
Verification must be runnable bash: jq/grep/curl on the repo, a local `python3 -m http.server` plus headless Chrome `--dump-dom`, or the live site.
-->

## Summary
<2-5 sentences describing the bug and its impact>

## Goal
After this fix:
1. ...
2. ...

## Current State
### Current behaviour
<what happens now: live site and/or `main` `<sha>`, with evidence>

### Expected behaviour
<what should happen>

### Reproduction
```bash
<commands that show the bug, e.g. curl/jq on the live site or headless Chrome --dump-dom>
```

## Implementation Details
### 1. <Component or area>
- <the chosen fix, and why it beats the alternatives>

## Files Likely Affected
| File | Change |
|------|--------|
| `path/to/file` | MODIFY + note |
| `CHANGELOG.md` | MODIFY: Fixed bullet in the next patch release section |

## Dependencies / Related Issues
- Part of: #...
- Depends on: #...

## Constraints / Non-Goals
- No new libraries, CDN `<script src>`/`<link>` or build tooling without an owner decision.
- Never hand-edit `data/`. The data bot commits right after every merge to `main` (`git add .`), so rebase before merge.
- Keep table column indices 0–10. Append any new CSV column **last** and keep it off the table unless the issue says otherwise.
- Existing URL params and shared links must behave as on `main`.
- Do not ...

## Acceptance Criteria
- [ ] The reproduction no longer shows the bug.
- [ ] Behaviour outside the fix is unchanged versus `main`.
- [ ] ...

## Verification
```bash
set -euo pipefail
<commands>
```
