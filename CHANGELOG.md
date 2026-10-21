# Changelog

## [0.0.18] - 2026-10-21

### Changed

- Consolidated table controls into a compact header, toolbar, and accessible More/Columns menus; search, filters, exports, and keyboard shortcuts retain their existing behaviour (closes #46)

### Fixed

- Restored the Dark theme button's light-mode text contrast

## [0.0.16] - 2026-10-21

### Added

- Static per-model pricing pages and a generated model sitemap (closes #30)

## [0.0.15] - 2026-10-21

### Fixed

- Report opposite-direction prompt/completion moves (each significant) whose 3:1 blended change is under the drop threshold as `mixed`; larger blended moves remain `increase`/`decrease`, and Atom feed entries have distinct deterministic update times (closes #40)

## [0.0.14] - 2026-10-21

### Added

- Price-changes Atom feed and “What changed” strip (closes #29)

## [0.0.13] - 2026-10-20

### Changed

- Refreshed CLAUDE.md to the current architecture (closes #24)

## [0.0.12] - 2026-10-20

### Added

- Favicon set for browser tabs, bookmarks, and Apple touch icons (closes #27)
- Static share image for Open Graph and Twitter link previews (closes #31)
- Relative, local-time display for the data update timestamp (closes #32)

### Changed

- Sitemap `lastmod` now tracks the data update date (closes #33)

### Fixed

- Visible model count now follows the loaded data; meta description no longer names GPT-4 (closes #34)

### Removed

- Broken PDF export button and dead Flash export plugin (closes #23)

## [0.0.11] - 2026-10-20

### Added

- **Advanced filters & side-by-side compare** (closes #3)
  - Context buckets, inclusive prompt/completion price bounds, input/output modality filters, and shareable filter state
  - Compare up to four models with raw prices, capabilities, modalities, price trends, and calculator hand-off

### Technical

- Shared epsilon price helper, URL-only advanced-filter state, and CSV input/output modality columns

## [0.0.10] - 2026-10-20

### Added

- **Model Finder & use-case presets** (closes #7)
  - Find up to 10 lowest-cost models by context, required capabilities, price limits, free-only status, and model ID/name
  - Includes editable presets for support, coding, RAG, extraction, reasoning, web research, and free experimentation
  - Copy-ready curl, JavaScript fetch, and Python OpenAI SDK snippets for a selected model

### Technical

- Finder state is shareable in compact URL parameters; ranking uses raw 3:1 prompt:completion prices and excludes variable/router pricing

## [0.0.9] - 2026-10-20

### Added

- **Cloudflare Web Analytics** (free tier, cookieless, edge-injected; closes #17)

## [0.0.8] - 2026-10-20

### Fixed

- Router/variable-price models (`-1` placeholder) show **n/a** instead of `-1000000.00` and sort last (7 models); any negative or unparseable price is also shown as n/a.
- Prompt/Completion columns now sort numerically (previously text order).

## [0.0.7] - 2026-10-20

### Added

- **Cost Calculator** (closes #4)
  - Compare prompt/completion token costs per request, day, 30-day month, 365-day year, and one-off batch across up to 10 models
  - Includes workload presets, a rough text-to-token estimate, favorites-aware defaults, shareable estimates, copy output, and CSV download

### Technical

- Calculator preserves raw USD/token pricing alongside the rounded table display, treats negative/router prices as n/a, and stores calculator state in URL parameters

## [0.0.6] - 2026-06-09

### Added

- **Price History & Trends** (closes #10; also delivers the abandoned #2)
  - Per-model price-history charts (dependency-free inline SVG, prompt + completion series) opened via a 📈 button on each table row and card
  - 30-day price-change badges (▲/▼ %) shown inline next to prompt and completion costs, with a "▼ free" badge when a model becomes free
  - Discontinued-models archive: a searchable list of every model removed from OpenRouter since tracking began (2024-09-21)
  - Backfilled from the repository's own git history — 957 commits / ~20 months of `data/output.json` — so the charts are populated from day one
- **Price-history ledger** `data/history/prices.json`: a compact change-point series per model (first/last seen, present/discontinued, prompt/completion in USD per 1M tokens)
- **`scripts/backfill_history.py`**: maintains the ledger. Incremental by default (folds the current snapshot; safe under a shallow CI checkout); `--rebuild` reconstructs it from full git history

### Changed

- `scripts/get_zipped.sh` now updates the price-history ledger after each data change (non-fatal — it can never block the core pricing update)
- The frontend loads `data/history/prices.json` before rendering the table; the feature degrades gracefully if the ledger is absent

### Technical

- Trend math reads a step-held price series (a price holds until the next recorded change); change badges threshold out sub-1% provider precision noise
- SVG charts use step-after interpolation and extend the latest price to the dataset's `as_of` date

## [0.0.5] - 2025-08-30

### Added

- **Comprehensive SEO Optimization**
  - Rich meta tags for improved search engine visibility
  - OpenGraph and Twitter Card tags for enhanced social media sharing
  - JSON-LD structured data for better search engine understanding
  - Canonical URL to prevent duplicate content issues
  - `robots.txt` file to guide search engine crawlers
  - `sitemap.xml` for improved indexing and discoverability
- **Semantic HTML5 Structure**
  - Converted layout to use semantic elements (header, main, footer, section)
  - Added ARIA labels for improved accessibility
  - Proper heading hierarchy with descriptive H1 and H2 tags
- **Enhanced Content & Copy**
  - More descriptive page title optimized for search queries
  - Keyword-rich meta description (160 characters)
  - Informative content sections explaining the tool's purpose and features
  - Footer with additional context and navigation links
- **README Improvements**
  - Professional badges for license, update status, and live website
  - Comprehensive feature lists and use cases
  - Data fields table with clear descriptions
  - Contributing section to encourage community involvement
  - Strategic keyword placement for GitHub SEO

### Changed

- Page title from "Open Router Models" to "OpenRouter Model Pricing & Comparison | AI Model Cost Calculator"
- Info section expanded with detailed feature descriptions and benefits
- All external links now include `rel="noopener"` for security
- README restructured with emojis and better organization

### Technical

- Added comprehensive meta tags covering SEO, OpenGraph, and Twitter Cards
- Implemented JSON-LD structured data schema for web applications
- Created SEO-friendly URL structure with canonical tags
- Optimized for crawling with robots.txt and XML sitemap

## [0.0.4] - 2025-08-16

### Added

- **Interactive Tooltips for Better UX**
  - Added helpful "?" icons with explanations for all capability filters
  - Tooltips explain what each capability means (Tool Calling, Structured Outputs, etc.)
  - Filter mode toggle tooltip clarifies "Match All" vs "Match Any" logic
  - Quick filter preset tooltips describe what each preset filters for
- **Enhanced Tooltip Features**
  - Theme-aware tooltips that adapt to light/dark mode
  - Mobile-friendly tooltips with tap-to-show functionality
  - Smooth animations and positioning above elements
  - Clear, concise explanations to help users understand filter options

### Changed

- Capability filter checkboxes restructured to accommodate tooltip icons
- Filter mode toggle wrapped for better tooltip positioning
- Preset buttons wrapped individually for tooltip support

## [0.0.3] - 2025-08-15

### Added

- **Model Capability Columns**: Added 5 new columns displaying model capabilities
  - Tool Calling (144 models supported)
  - Structured Outputs (142 models supported)
  - Reasoning (90 models supported)
  - Response Format (185 models supported)
  - Web Search (16 models supported)
- **Advanced Capability Filtering System**
  - Filter models by required capabilities with Match All/Match Any modes
  - Quick filter presets for common use cases (Agentic, Reasoning, Structured, Web-Enabled)
  - Visual indicators showing active filter count and matching models
  - Real-time filtering with DataTables integration
- **Enhanced Keyboard Shortcuts**
  - `c` - Focus capability filters
  - `m` - Toggle filter mode (Match All/Any)
  - `x` - Clear all capability filters
- **Improved URL State Management**
  - Capability filters are now persisted in URL for sharing
  - Filter mode preference saved in URL parameters

### Changed

- Updated `get_zipped.sh` script to extract capability data from OpenRouter API's `supported_parameters` field
- Card view now respects capability filters in addition to favorites
- Column visibility toggles extended to support new capability columns
- Mobile interface optimized for capability filter controls

### Technical

- Implemented custom DataTables search extension for capability filtering
- Added complex jq parsing logic for capability detection in bash script
- Enhanced state management to handle multiple filter types simultaneously

## [0.0.2] - 2025-08-15

### Added

- Dark/Light theme toggle with system preference detection
- Favorite models functionality with localStorage persistence
- Shareable URLs that preserve filter/search state
- Keyboard shortcuts for power users (/, f, t, d, v, e, ?, Esc)
- Mobile-responsive card view layout for better mobile experience
- Column show/hide customization options
- Density options (Compact/Comfortable/Spacious) for row heights
- Help modal showing all keyboard shortcuts
- Modern styled export buttons with icons

### Changed

- Updated color scheme from green to modern blue (#2563eb light, #3b82f6 dark)
- Improved dark mode with better contrast and visibility
- Modernized UI with smooth transitions and animations
- Enhanced DataTables button styling with icons and hover effects

### Fixed

- Dark mode table cell background colors now display correctly
- Density toggle functionality now properly changes table padding
- Text contrast improved in dark mode for better readability

## [0.0.1] - 2024-09-21

### Added

- Initial release of the project.
