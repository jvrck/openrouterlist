#!/usr/bin/env python3
"""Maintain data/history/prices.json — a compact price-history ledger for the
OpenRouter models tracked by this repo.

Two modes, one shared mutator (apply_snapshot) so they can never drift:

  * incremental (default): fold the CURRENT data/output.json into the existing
    ledger. O(models), needs no git history, so it is safe under a shallow CI
    checkout. This is what the daily GitHub Action runs.

  * --rebuild: reconstruct the whole ledger from scratch by walking every commit
    that touched data/output.json (git is the 20-month price archive), then fold
    in the working tree. Run this once to seed the ledger, or any time to repair
    it. Needs full git history (run locally / fetch-depth: 0).

Ledger shape (per model id):
    {name, first_seen, last_seen, present_now, points: [[YYYY-MM-DD, prompt, completion], ...]}
Prices are USD per 1,000,000 tokens (display units); null = unpriced / -1 sentinel.
points records only CHANGE points, so a flat model is a single point.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "output.json")
UPDATED = os.path.join(ROOT, "data", "updated")
LEDGER = os.path.join(ROOT, "data", "history", "prices.json")
EXCLUDE = {"openrouter/auto"}  # -1 pricing sentinel; the site excludes it too
LEDGER_FLOOR = 50  # a healthy ledger has hundreds of models; fewer => empty/corrupt, refuse to use


def per_million(v):
    """Per-token price string -> USD per 1M tokens, or None for missing / -1 sentinel."""
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return None if f < 0 else round(f * 1_000_000, 6)


def parse_snapshot(text):
    """Raw output.json text -> {id: (name, prompt_per_1m, completion_per_1m)}."""
    snap = {}
    for m in (json.loads(text).get("data") or []):
        if not isinstance(m, dict):
            continue
        mid = m.get("id")
        if not mid or mid in EXCLUDE:
            continue
        pr = m.get("pricing")
        pr = pr if isinstance(pr, dict) else {}
        snap[mid] = (m.get("name", mid), per_million(pr.get("prompt")), per_million(pr.get("completion")))
    return snap


def apply_snapshot(models, day, snap):
    """Fold one dated snapshot into the ledger in place. Shared by both modes."""
    for mid, (name, p, c) in snap.items():
        rec = models.get(mid)
        if rec is None:
            models[mid] = {"name": name, "first_seen": day, "last_seen": day,
                           "present_now": True, "points": [[day, p, c]]}
        else:
            rec["name"] = name
            rec["last_seen"] = day
            last = rec["points"][-1]
            if [last[1], last[2]] != [p, c]:
                rec["points"].append([day, p, c])


def set_present(models, current_ids):
    for mid, rec in models.items():
        rec["present_now"] = mid in current_ids


def updated_day():
    """YYYY-MM-DD from data/updated (format YYYYMMDD_HHMMSS); '' if unreadable."""
    try:
        with open(UPDATED) as f:
            s = f.read().strip()
        return f"{s[0:4]}-{s[4:6]}-{s[6:8]}"
    except OSError:
        return ""


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True)


def rebuild():
    log = git("log", "--reverse", "--format=%H\t%cI", "--", "data/output.json")
    commits = [ln.split("\t") for ln in log.stdout.strip().splitlines() if "\t" in ln]
    if not commits:
        sys.exit("rebuild needs full git history for data/output.json (run with fetch-depth: 0)")
    commits.sort(key=lambda c: c[1])  # by committer ISO date; git log order isn't guaranteed %cI-ascending
    models = {}
    for sha, iso in commits:
        show = git("show", f"{sha}:data/output.json")
        if show.returncode != 0:
            continue
        try:
            snap = parse_snapshot(show.stdout)
        except json.JSONDecodeError:
            continue
        apply_snapshot(models, iso[:10], snap)
    current = fold_working_tree(models)
    set_present(models, current)
    write(models)
    print(f"rebuilt from {len(commits)} snapshots -> {len(models)} models")


def incremental():
    try:
        with open(LEDGER) as f:
            models = json.load(f).get("models", {})
        if not isinstance(models, dict) or len(models) < LEDGER_FLOOR:
            raise ValueError(f"only {len(models) if isinstance(models, dict) else 'invalid'} models (< floor {LEDGER_FLOOR})")
    except (OSError, json.JSONDecodeError, ValueError) as e:
        # Empty/truncated/corrupt ledger: don't fold-and-gut it; self-heal from git instead.
        print(f"WARN: existing ledger unusable ({e}); rebuilding from git history")
        return rebuild()
    prev_count = len(models)
    current = fold_working_tree(models)
    set_present(models, current)
    write(models, prev_count)
    print(f"folded current snapshot -> {len(models)} models ({sum(v['present_now'] for v in models.values())} present)")


def fold_working_tree(models):
    """Apply the working-tree data/output.json as the latest snapshot. Returns its id set."""
    with open(DATA) as f:
        snap = parse_snapshot(f.read())
    day = updated_day() or (models and max(r["last_seen"] for r in models.values())) or "1970-01-01"
    apply_snapshot(models, day, snap)
    return set(snap)


def write(models, prev_count=0):
    if prev_count and len(models) < prev_count * 0.5:
        sys.exit(f"refusing to write: {len(models)} models < 50% of previous {prev_count} (ledger looks corrupt; run --rebuild)")
    as_of = max((r["last_seen"] for r in models.values()), default="")
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    payload = {"as_of": as_of, "model_count": len(models), "models": models}
    tmp = LEDGER + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f, separators=(",", ":"))
    os.replace(tmp, LEDGER)  # atomic on POSIX — a kill mid-write can't truncate the live ledger
    print(f"wrote {LEDGER} ({os.path.getsize(LEDGER):,} bytes, as_of {as_of})")


if __name__ == "__main__":
    if "--rebuild" in sys.argv[1:] or not os.path.exists(LEDGER):
        rebuild()
    else:
        incremental()
