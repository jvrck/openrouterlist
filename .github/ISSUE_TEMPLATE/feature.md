---
name: Feature
about: A new capability or substantial enhancement.
title: 'feat: <action-oriented title>'
---

<!--
Follow the fspec Issue Authoring Guide: https://github.com/jvrck-labs/fspec/blob/main/docs/ISSUE_AUTHORING_GUIDE.md
The test: a fresh agent can do this issue with no questions. One unit of work per issue.
Base Current State and Files on `main` (index.html, scripts/, .github/workflows/, data/): name the commit, functions, element ids and line numbers you checked.
Verification must be runnable bash: jq/grep/curl on the repo, a local `python3 -m http.server` plus headless Chrome `--dump-dom`, or the live site.
Features larger than ~1 week of work probably belong in an EPIC with sub-issues.
-->

## Summary
<2-5 sentences describing the change, the current problem, and why it matters>

## Goal
After this change:
1. ...
2. ...
3. ...

## Current State
At `main` `<sha>`:
- <what exists today, with file/function/id/line references>
- ...

## Implementation Details
### 1. <Component or area>
- ...

### 2. <Component or area>
- ...

## Files Likely Affected
| File | Change |
|------|--------|
| `index.html` | MODIFY + note |
| `CHANGELOG.md` | MODIFY: bullet in the next patch release section (site-visible changes only) |

## Dependencies / Related Issues
- Part of: #...
- Depends on: #...
- Blocks: #...

## Constraints / Non-Goals
- No new libraries, CDN `<script src>`/`<link>` or build tooling without an owner decision.
- Never hand-edit `data/`. The data bot commits right after every merge to `main` (`git add .`), so rebase before merge.
- Keep table column indices 0–10. Append any new CSV column **last** and keep it off the table unless the issue says otherwise.
- Existing URL params and shared links must behave as on `main`.
- Do not ...

## Acceptance Criteria
- [ ] ...
- [ ] ...
- [ ] The change set contains only the files listed above.

## Verification
```bash
set -euo pipefail
# e.g. serve locally and inspect the rendered page:
# python3 -m http.server 8817 --bind 127.0.0.1 >/dev/null 2>&1 & SRV=$!; trap 'kill $SRV' EXIT; sleep 1
# "${CHROME:-google-chrome}" --headless=new --virtual-time-budget=15000 --dump-dom http://127.0.0.1:8817/ | grep -q '...'
<commands>
```
