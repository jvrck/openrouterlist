---
name: Spike
about: Time-boxed research or investigation to reduce uncertainty.
title: 'spike: <action-oriented title>'
---

<!--
Follow the fspec Issue Authoring Guide: https://github.com/jvrck-labs/fspec/blob/main/docs/ISSUE_AUTHORING_GUIDE.md
The test: a fresh agent can do this issue with no questions. One unit of work per issue.
Base Current State and Files on `main` (index.html, scripts/, .github/workflows/, data/): name the commit, functions, element ids and line numbers you checked.
Verification must be runnable bash: jq/grep/curl on the repo, a local `python3 -m http.server` plus headless Chrome `--dump-dom`, or the live site.
-->
A Spike's deliverable is a documented finding, not product code.

## Summary
<2-5 sentences: what unknown is being resolved, and why it matters now>

## Goal
After this spike:
1. <documented finding>
2. <where the finding lands, e.g. a comment on this issue plus an update to the blocked issue>

## Current State
- <what is known today, with sources and dates>

## Implementation Details
### Investigation questions
1. ...
2. ...

### Method
- ...

### Time box
<e.g. 2 hours, and what happens if it's exceeded>

## Files Likely Affected
| File | Change |
|------|--------|
| (usually none) | The finding goes in an issue comment |

## Dependencies / Related Issues
- Blocks: #...

## Constraints / Non-Goals
- No implementation work that depends on the finding (open a follow-up).
- Don't contact third parties or change external state; draft any ask instead.

## Acceptance Criteria
- [ ] Every investigation question is answered, with sources.
- [ ] The verdict is stated, and the blocked issue is updated or a follow-up is opened.
- [ ] The spike is closed with a comment summarising the outcome.

## Verification
```bash
set -euo pipefail
gh issue view <this-issue> -R jvrck/openrouterlist --comments | grep -Eiq 'verdict:'
```
