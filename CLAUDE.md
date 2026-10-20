# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

OpenRouterList is a static model-pricing site at https://openrouterlist.jvrck.com. GitHub Pages serves `main`; `CNAME` supplies the custom domain. The application is a single `index.html` with inline CSS and JavaScript. There is no build step, test suite, or pull-request CI. Related static files include `sitemap.xml`, `robots.txt`, favicons, and the static `og-image.png` share image.

## Key commands

```bash
# Fetch the live API and update local data if it changed; requires jq, curl, zip, and python3.
bash ./scripts/get_zipped.sh

# Fold the current snapshot into the price ledger. --rebuild instead replays full Git history.
python3 scripts/backfill_history.py [--rebuild]

# Preview the static site locally.
python3 -m http.server
```

Run the data-changing commands only in a scratch copy when investigating: `get_zipped.sh` contacts the live API, and every invocation of `backfill_history.py` writes `data/history/prices.json`. The history script has no `--help`; an unrecognised argument still performs its normal incremental update. `--rebuild` requires full history (`fetch-depth: 0`).

## Data flow and files

`scripts/get_zipped.sh` fetches OpenRouter's `/api/v1/models`, writes a timestamped local result under `results/`, and creates `data/output.csv` from the response. `results/` is local and gitignored. Only when `data/output.json` differs does the script copy the JSON and CSV into `data/`, write `data/updated`, and invoke the incremental history update (non-fatally).

`data/output.csv` has these 13 columns, in order:

`id`, `name`, `created`, `context_length`, `pricing.prompt`, `pricing.completion`, `tool_calling`, `structured_outputs`, `reasoning`, `response_format`, `web_search`, `input_modalities`, `output_modalities`.

The five capability values are derived from `supported_parameters`: `tool_calling` requires both `tools` and `tool_choice`; `structured_outputs` requires `structured_outputs`; `reasoning` accepts `reasoning` or `include_reasoning`; `response_format` requires `response_format`; and `web_search` requires `web_search_options`. The modality values are pipe-delimited. The table displays the first 11 columns; the two modality columns feed filters and cards rather than table columns.

`data/updated` is a UTC `YYYYMMDD_HHMMSS` stamp, changed only when the source data changes. The page load sequence is `data/updated`, then `data/history/prices.json` (non-fatal), then `data/output.csv`. `parseUpdatedStamp` parses the timestamp as UTC and `renderUpdatedDate` presents the relative “Updated … ago” text.

`data/history/prices.json` is a compact ledger with top-level `as_of`, `model_count`, and `models`. Each model ID maps to `{name, first_seen, last_seen, present_now, points}`, where `points` contains `[date, prompt, completion]` change points. Prices are USD per 1M tokens and `null` means unpriced. The incremental mode folds the current snapshot; `--rebuild` reconstructs the ledger from the repository's historical snapshots.

## Automation

`.github/workflows/daily_run.yml` runs on cron at 00:00 and 12:00 UTC, `workflow_dispatch`, and push to `main`. It runs the fetch script, updates sitemap `lastmod` from `data/updated`, then uses `git add .` and commits only when there is a change. Its push uses `GITHUB_TOKEN`, which does not start a loop. The workflow uploads nothing; `results/` is local and gitignored.

The data bot can commit immediately after a merge. Rebase before merging, and never hand-edit `data/`.

## Frontend map

`index.html` uses pinned CDN libraries: jQuery 3.6.0, DataTables 1.11.5, DataTables Buttons 1.7.1, and JSZip 3.1.3. Do not add a library without a maintainer decision.

The `$.fn.dataTable.ext.search` predicate is the single capability and advanced-filter path. Cards derive from the table's applied rows. Features include capability filters (All/Any), quick filters, Clear All, advanced context/price/modality filters and Text-only, favourites, column toggles, themes, density, and a card view at 768 px or narrower. Favourites use an escaped, anchored exact-ID match.

`#finderModal` ranks up to 10 matching models by a 3:1 prompt-to-completion blend. `#calculatorModal` compares costs for up to 10 models. `#compareModal` holds up to 4 models. `#historyModal` shows price history and 30-day badges; `#discontinuedModal` lists models no longer present. The available exports are Copy, CSV, Excel, and Print; there is no PDF or Flash export.

Keyboard shortcuts are `/`, `f`, `t`, `d`, `v`, `e`, `c`, `m`, `x`, `k`, `g`, `?`, and Escape.

URL state is read with these parameter names: `search`, `favorites`, `theme`, `density`, `capabilities`, `capMode`, `columns`, `calc`, `cp`, `cc`, `cr`, `cb`, `cm`, `finder`, `fu`, `fx`, `fk`, `fpp`, `fpc`, `ff`, `fq`, `fs`, `afx`, `ctx`, `ppmin`, `ppmax`, `pcmin`, `pcmax`, `min`, `mout`, `mto`, and `cmp`. Persistent local state is limited to `favorites`, `theme`, `density`, and `columnVisibility`; filters otherwise live in the URL.

## Gotchas

- `-1` represents router or variable pricing: it is shown as n/a, sorted last, and excluded from price ranges. `openrouter/free` at 0/0 is genuinely free, not variable-priced.
- Use the epsilon helper for every price comparison; its tolerance is `Number.EPSILON * max(1, abs(limit))` (approximately `8.25e-7 * 1e6` at the relevant display scale).
- Deduplicate before capping model IDs restored from URLs: `cm` caps at 10 and `cmp` caps at 4.
- Append new CSV columns last and keep them out of the table: `columns` and `columnVisibility` are index-based. Modalities are pipe-delimited, while the CSV row parser still has a latent `split(',')` assumption.
- The modality UI must hide gracefully when supplied an 11-column CSV with no modality fields.
- Context buckets use the 32,768, 131,072, and 262,144 edges.
- Static metadata and Open Graph content remain static because crawlers do not run JavaScript. The meta description retains its static “400+” wording while `modelCount` is updated from the loaded data.
- There is no PR CI: verify browser-facing changes in headless Chrome. Keep verification portable across macOS/BSD and GNU tools; do not rely on `date -d` or bare `sed -i`.

## Analytics

Cloudflare Web Analytics is zone-wide for jvrck.com, edge-injected, on the free tier, and has no custom events. There is no beacon in this repository.

## Conventions

Make one CHANGELOG patch bump per PR, with no `Unreleased` section. Use type-prefixed PR titles. Keep screenshots in `docs/screenshots/`.
