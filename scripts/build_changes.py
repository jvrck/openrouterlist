#!/usr/bin/env python3
"""Build recent price changes for the site strip and Atom feed.

Inputs are the price-history ledger and current OpenRouter snapshot. This is a
read-only derivation: validate everything before atomically replacing outputs.
"""
import datetime as dt
import html
import json
import math
import os
import sys
import tempfile
from urllib.parse import quote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "data", "history", "prices.json")
SNAPSHOT = os.path.join(ROOT, "data", "output.json")
CHANGES = os.path.join(ROOT, "data", "changes.json")
FEED = os.path.join(ROOT, "feed.xml")
WINDOW_DAYS = 30
EPSILON = 1e-12
SITE = "https://openrouterlist.jvrck.com"


def fail(message):
    raise ValueError(message)


def parse_day(value, label):
    if not isinstance(value, str):
        fail(f"{label} must be YYYY-MM-DD")
    try:
        parsed = dt.date.fromisoformat(value)
    except ValueError:
        fail(f"{label} must be YYYY-MM-DD")
    if parsed.isoformat() != value:
        fail(f"{label} must be YYYY-MM-DD")
    return parsed


def price(value, label):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{label} must be a number or null")
    value = float(value)
    if not math.isfinite(value) or value < 0:
        fail(f"{label} must be a finite non-negative number or null")
    return value


def blended(point):
    prompt, completion = point
    return None if prompt is None or completion is None else (3 * prompt + completion) / 4


def zero(value):
    return abs(value) < EPSILON


def price_text(value):
    if value is None:
        return "n/a"
    rendered = f"{value:,.6f}".rstrip("0").rstrip(".")
    if "." not in rendered:
        rendered += ".00"
    elif len(rendered.rsplit(".", 1)[1]) == 1:
        rendered += "0"
    return f"${rendered}"


def changed_fields(old, new):
    fields = []
    for label, old_value, new_value in (("prompt", old[0], new[0]), ("completion", old[1], new[1])):
        if old_value != new_value:
            fields.append(f"{label} {price_text(old_value)} → {price_text(new_value)} /1M")
    return "; ".join(fields) or "price updated"


def load_json(path, label):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except OSError as error:
        fail(f"cannot read {label}: {error}")
    except json.JSONDecodeError as error:
        fail(f"invalid JSON in {label}: {error.msg}")


def latest_daily_points(raw_points, model_id):
    if not isinstance(raw_points, list) or not raw_points:
        fail(f"{model_id}.points must be a non-empty list")
    by_day = {}
    for index, raw in enumerate(raw_points):
        if not isinstance(raw, list) or len(raw) != 3:
            fail(f"{model_id}.points[{index}] must be [date, prompt, completion]")
        day = parse_day(raw[0], f"{model_id}.points[{index}][0]")
        # Points are append ordered: final same-day point wins.
        by_day[day] = (price(raw[1], f"{model_id}.points[{index}][1]"),
                       price(raw[2], f"{model_id}.points[{index}][2]"))
    return sorted(by_day.items())


def build_changes(ledger, snapshot):
    if not isinstance(ledger, dict) or not isinstance(ledger.get("models"), dict):
        fail("prices.json must contain a models object")
    as_of = parse_day(ledger.get("as_of"), "prices.json.as_of")
    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("data"), list):
        fail("output.json must contain a data array")
    output_by_id = {}
    for index, item in enumerate(snapshot["data"]):
        if not isinstance(item, dict) or not isinstance(item.get("id"), str) or not item["id"]:
            fail(f"output.json.data[{index}] must have an id")
        output_by_id[item["id"]] = item

    cutoff = as_of - dt.timedelta(days=WINDOW_DAYS)
    price_changes, new_models, removed_models = [], [], []
    for model_id in sorted(ledger["models"]):
        record = ledger["models"][model_id]
        if not isinstance(model_id, str) or not model_id or not isinstance(record, dict):
            fail("prices.json.models must map non-empty ids to objects")
        name = record.get("name") if isinstance(record.get("name"), str) and record["name"] else model_id
        first_seen = parse_day(record.get("first_seen"), f"{model_id}.first_seen")
        last_seen = parse_day(record.get("last_seen"), f"{model_id}.last_seen")
        if cutoff < first_seen <= as_of:
            new_models.append({"id": model_id, "name": name, "first_seen": first_seen.isoformat()})
        if record.get("present_now") is False and cutoff < last_seen <= as_of:
            removed_models.append({"id": model_id, "name": name, "last_seen": last_seen.isoformat()})
        daily = latest_daily_points(record.get("points"), model_id)
        for (old_day, old), (new_day, new) in zip(daily, daily[1:]):
            if not cutoff < new_day <= as_of:
                continue
            if old == new:
                continue
            old_blended, new_blended = blended(old), blended(new)
            if new_blended is None:
                continue
            if old_blended is None:
                if new_blended <= EPSILON:
                    continue
                kind, true_pct = "became_priced", None
            elif zero(old_blended):
                if zero(new_blended):
                    continue
                kind, true_pct = "became_priced", None
            elif old_blended > EPSILON and zero(new_blended):
                kind, true_pct = "went_free", ((new_blended - old_blended) / old_blended) * 100
            else:
                true_pct = ((new_blended - old_blended) / old_blended) * 100
                kind = "increase" if new_blended > old_blended else "decrease"
            if true_pct is not None and abs(true_pct) < 1 and abs(new_blended - old_blended) < 0.01:
                continue
            pct = None if old_blended is None or old_blended < 0.01 else true_pct
            price_changes.append({"id": model_id, "name": name, "date": new_day.isoformat(), "kind": kind,
                                  "prompt": [old[0], new[0]], "completion": [old[1], new[1]], "pct": pct})

    retiring = []
    for model_id, item in output_by_id.items():
        expiration = item.get("expiration_date")
        if expiration is None:
            continue
        try:
            expiration_day = parse_day(expiration, f"output.json {model_id}.expiration_date")
        except ValueError:
            print(f"WARN: skipping invalid expiration_date for {model_id}: {expiration!r}", file=sys.stderr)
            continue
        if expiration_day >= as_of:
            name = item.get("name") if isinstance(item.get("name"), str) and item["name"] else model_id
            retiring.append({"id": model_id, "name": name, "expiration_date": expiration_day.isoformat()})
    price_changes.sort(key=lambda item: (-parse_day(item["date"], "change date").toordinal(), item["id"], item["kind"]))
    new_models.sort(key=lambda item: (-parse_day(item["first_seen"], "new-model date").toordinal(), item["id"]))
    removed_models.sort(key=lambda item: (-parse_day(item["last_seen"], "removed-model date").toordinal(), item["id"]))
    retiring.sort(key=lambda item: (item["expiration_date"], item["id"]))
    return {"as_of": as_of.isoformat(), "window_days": WINDOW_DAYS, "price_changes": price_changes,
            "new_models": new_models, "removed_models": removed_models, "retiring": retiring}


def feed_for(changes):
    as_of = changes["as_of"]
    events = []
    for item in changes["price_changes"]:
        events.append((item["date"], item["id"], item["kind"], item))
    for item in changes["new_models"]:
        events.append((item["first_seen"], item["id"], "new_model", item))
    for item in changes["removed_models"]:
        events.append((item["last_seen"], item["id"], "removed_model", item))
    events.sort(key=lambda event: (-parse_day(event[0], "feed event date").toordinal(), event[1], event[2]))
    text = lambda value: html.escape(str(value), quote=True)
    entries = []
    for day, model_id, kind, item in events[:50]:
        if kind in ("new_model", "removed_model"):
            action = "new model" if kind == "new_model" else "removed model"
            title = f"{item['name']}: {action}"
            summary = title
        else:
            old = (item["prompt"][0], item["completion"][0])
            new = (item["prompt"][1], item["completion"][1])
            title = f"{item['name']}: {changed_fields(old, new)}"
            summary = f"{item['kind'].replace('_', ' ')}: {changed_fields(old, new)}"
        tag_id = quote(model_id, safe="-._~:/@!$&'()*+,;=%")
        href = f"{SITE}/?search={quote(model_id, safe='')}"
        entries.append("  <entry>\n"
                       f"    <id>tag:openrouterlist.jvrck.com,{text(day)}:{text(kind)}:{text(tag_id)}</id>\n"
                       f"    <title>{text(title)}</title>\n"
                       f"    <updated>{text(day)}T00:00:00Z</updated>\n"
                       f"    <link rel=\"alternate\" href=\"{text(href)}\"/>\n"
                       f"    <summary>{text(summary)}</summary>\n"
                       "  </entry>")
    return ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
            "  <title>OpenRouterList price changes</title>\n"
            "  <subtitle>Recent OpenRouter model pricing, additions, and removals</subtitle>\n"
            "  <id>tag:openrouterlist.jvrck.com,2026:feed</id>\n"
            f"  <updated>{as_of}T00:00:00Z</updated>\n"
            "  <author><name>OpenRouterList</name></author>\n"
            f"  <link rel=\"self\" href=\"{SITE}/feed.xml\"/>\n"
            f"  <link rel=\"alternate\" href=\"{SITE}/\"/>\n"
            + ("\n".join(entries) + "\n" if entries else "") + "</feed>\n")


def write_temp(path, content):
    descriptor, temporary = tempfile.mkstemp(prefix=".build_changes-", dir=os.path.dirname(path))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
        return temporary
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def atomic_write_pair(first_path, first_content, second_path, second_content):
    """Prepare both complete files before replacing either generated output."""
    first_temp = second_temp = None
    try:
        first_temp = write_temp(first_path, first_content)
        second_temp = write_temp(second_path, second_content)
        os.replace(first_temp, first_path)
        first_temp = None
        os.replace(second_temp, second_path)
        second_temp = None
    finally:
        for temporary in (first_temp, second_temp):
            if temporary:
                try:
                    os.unlink(temporary)
                except OSError:
                    pass


def main():
    changes = build_changes(load_json(LEDGER, "data/history/prices.json"), load_json(SNAPSHOT, "data/output.json"))
    changes_text = json.dumps(changes, separators=(",", ":"), sort_keys=True, ensure_ascii=False) + "\n"
    feed_text = feed_for(changes)
    atomic_write_pair(CHANGES, changes_text, FEED, feed_text)
    print(f"wrote {CHANGES} and {FEED} ({len(changes['price_changes'])} price changes)")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"build_changes.py: {error}", file=sys.stderr)
        sys.exit(1)
