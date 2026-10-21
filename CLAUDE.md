# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

OpenRouterList is a static model-pricing site at https://openrouterlist.jvrck.com. GitHub Pages serves `main`; `CNAME` supplies the custom domain. The application is a single `index.html` with inline CSS and JavaScript. There is no site build step, test suite, or pull-request CI. Related static files include `sitemap.xml`, `robots.txt`, `llms.txt`, the documented `api/` outputs, generated model pages in `m/`, favicons, and the static `og-image.png` share image.

## Key commands

```bash
# Use a scratch copy: hits the live API and can rewrite `data/`; requires jq, curl, zip, and python3.
bash ./scripts/get_zipped.sh

# Use a scratch copy: always writes `data/history/prices.json`; no `--help`, and unknown args run incrementally. `--rebuild` needs full history (`fetch-depth: 0`).
python3 scripts/backfill_history.py [--rebuild]

# Regenerate the stable JSON API and model pages from current data.
bash scripts/build_api.sh
bash scripts/build_model_pages.sh

# Preview the static site locally.
python3 -m http.server
```

## Data flow and files

`scripts/get_zipped.sh` first creates an empty `data/output.json` when it is missing. It fetches OpenRouter's `/api/v1/models`, writes `output.json` and the jq-built 13-column `output.csv` into a timestamped `results/output_<ts>/` directory, then compares that JSON with `data/output.json`. Only when `cmp` finds a difference does the script copy both files into `data/`, write `data/updated`, and invoke the incremental `backfill_history.py` update, `build_changes.py` derivation, `build_model_pages.sh` static-page/sitemap generation, and `build_api.sh` API projection (all non-fatally). `build_changes.py` turns the ledger and current snapshot into `data/changes.json` and `feed.xml`; opposite-direction prompt/completion moves (each significant) whose 3:1 blended change is under the drop threshold are `mixed`, while larger blended moves remain `increase`/`decrease`, and feed updates use deterministic per-day second offsets. `build_model_pages.sh` writes one current-model page beneath `m/`, records its template revision in `m/.template-version`, and rebuilds on a no-change fetch when that revision is missing or stale. `build_api.sh` writes the sorted, versioned `api/models.json`; a no-change fetch bootstraps it when missing. It then zips the results directory and deletes `results/output_<ts>/`. `results/` is local and gitignored.

`data/output.csv` has these 13 columns, in order:

`id`, `name`, `created`, `context_length`, `pricing.prompt`, `pricing.completion`, `tool_calling`, `structured_outputs`, `reasoning`, `response_format`, `web_search`, `input_modalities`, `output_modalities`.

The five capability values are derived from `supported_parameters` through `scripts/capabilities.jq`, shared by the CSV, API, and model summaries: `tool_calling` requires both `tools` and `tool_choice`; `structured_outputs` requires `structured_outputs`; `reasoning` accepts `reasoning` or `include_reasoning`; `response_format` requires `response_format`; and `web_search` requires `web_search_options`. The modality values are pipe-delimited. The table displays the first 11 columns; the two modality columns feed filters and cards rather than table columns.

`data/updated` is a UTC `YYYYMMDD_HHMMSS` stamp, changed only when the source data changes. The page fetches it independently with `$.get`. `loadHistoryThenTable` fetches `data/history/prices.json` with `.always` (so failure is non-fatal), then fetches `data/output.csv` and populates `allData`. `parseUpdatedStamp` parses the timestamp as UTC and `renderUpdatedDate` presents the relative “Updated … ago” text.

`data/history/prices.json` is a compact ledger with top-level `as_of`, `model_count`, and `models`. Each model ID maps to `{name, first_seen, last_seen, present_now, points}`, where `points` contains `[date, prompt, completion]` change points. Prices are USD per 1M tokens and `null` means unpriced. The incremental mode folds the current snapshot; `--rebuild` reconstructs the ledger from the repository's historical snapshots.

## Automation

`.github/workflows/daily_run.yml` runs on cron at 00:00 and 12:00 UTC, `workflow_dispatch`, and push to `main`. It runs the fetch script, which generates `m/`, `api/models.json`, and sitemap `lastmod` from `data/updated` when data changes, then uses `git add .` and commits only when there is a change. Its push uses `GITHUB_TOKEN`, which does not start a loop. The workflow uploads nothing; `results/` is local and gitignored.

The data bot can commit immediately after a merge. Rebase before merging, and never hand-edit `data/`.

## Frontend map

`index.html` uses pinned CDN libraries: jQuery 3.6.0, DataTables 1.11.5, DataTables Buttons 1.7.1, and JSZip 3.1.3. Do not add a library without a maintainer decision.

The `$.fn.dataTable.ext.search` predicate is the single capability and advanced-filter path. DataTables renders 50 rows at a time without its native pager; `#showMoreBtn` increases the table page length or the Card View slice by 50. Cards derive from the table's applied rows, and Card View search uses the same live `#globalSearch` query. The compact header contains `#globalSearch`, calculator/finder, and a More menu for theme, density, discontinued, help, and DataTables exports; the toolbar opens Filters and Columns panels. Features include capability filters (All/Any), quick filters, Clear All, advanced context/price/modality filters and Text-only, favourites, column toggles, themes, density, and a card view at 768 px or narrower. On phones, first visits start in cards and an explicit view toggle persists `viewMode`; desktop starts in the table. Favourites use an escaped, anchored exact-ID match.

`#changesStrip` independently loads `data/changes.json` for its movers, new, and retiring lists, links to `feed.xml`, and is collapsed on each load; it stays hidden until generated data exists. `#finderModal` ranks up to 10 matching models by a 3:1 prompt-to-completion blend. `#calculatorModal` compares costs for up to 10 models. `#compareModal` holds up to 4 models. `#historyModal` shows each model's price chart, tracked first/last-seen range, and 30-day change; its 30-day trend badges render in the table's price cells. `#discontinuedModal` lists models no longer present. The available exports are Copy, CSV, Excel, and Print; there is no PDF or Flash export.

Keyboard shortcuts: `/` focuses search; `f` toggles favourites; `t` cycles theme; `d` cycles density; `v` toggles card view only at 768 px or narrower; `e` exports CSV; `c` opens Filters and focuses the first capability filter; `m` toggles All/Any; `x` clears all filters; `k` opens the calculator; `g` opens the finder; `?` shows `#shortcutsModal`; Escape closes menus, calculator, finder, compare, and other modals.

URL state is grouped by feature: table/view: `search`, `favorites`, `theme`, `density`, `capabilities`, `capMode`, `columns`; calculator: `calc`, `cp`, `cc`, `cr`, `cb`, `cm`; finder: `finder`, `fu`, `fx`, `fk`, `fpp`, `fpc`, `ff`, `fq`, `fs`; advanced filters: `afx`, `ctx`, `ppmin`, `ppmax`, `pcmin`, `pcmax`, `min`, `mout`, `mto`; compare: `cmp`. Persistent local state is limited to `favorites`, `theme`, `density`, `columnVisibility`, and the explicit mobile `viewMode`; filters and the Show more length otherwise live only in the URL/session.

## Gotchas

- `-1` represents router or variable pricing: it is shown as n/a, sorted last, and excluded from price ranges. `openrouter/free` at 0/0 is genuinely free, not variable-priced.
- Price-bound checks use `priceWithinBounds` with tolerance `Number.EPSILON * Math.max(1, Math.abs(limit))`. Per-token USD multiplied by 1e6 is not exact (for example, `8.25e-7 * 1e6` is `0.8250000000000001`), so strict `>` comparisons can exclude boundary models.
- Deduplicate before capping model IDs restored from URLs: `cm` caps at 10 and `cmp` caps at 4.
- Append new CSV columns last and keep them out of the table: `columns` and `columnVisibility` are index-based. Modalities are pipe-delimited. The CSV row parser uses raw `split(',')`, so a quoted field containing a comma (such as a model name) would shift columns; do not introduce such fields or fix the parser in passing.
- The modality UI must hide gracefully when supplied an 11-column CSV with no modality fields.
- Context buckets use the 32,768, 131,072, and 262,144 edges.
- Static metadata and Open Graph content remain static because crawlers do not run JavaScript. The meta description retains its static “400+” wording while `modelCount` is updated from the loaded data.
- There is no PR CI: verify browser-facing changes in headless Chrome. Keep verification portable across macOS/BSD and GNU tools; do not rely on `date -d` or bare `sed -i`.

## Analytics

Cloudflare Web Analytics is zone-wide for jvrck.com, edge-injected, on the free tier, and has no custom events. There is no beacon in this repository.

## Conventions

Make one CHANGELOG patch bump per PR, with no `Unreleased` section. Use type-prefixed PR titles. Keep screenshots in `docs/screenshots/`.
