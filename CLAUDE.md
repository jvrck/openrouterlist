# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the OpenRouter Model Information and Pricing project that fetches and displays pricing data from OpenRouter's API. The project automatically updates model pricing data every 12 hours via GitHub Actions and displays it in a searchable, exportable HTML table hosted on GitHub Pages at https://jvrck.github.io/openrouterlist/.

## Key Commands

### Manual Data Update
```bash
bash ./scripts/get_zipped.sh
```
This script:
- Fetches latest model data from OpenRouter API
- Converts JSON to CSV format
- Creates timestamped results in `results/` directory
- Updates `data/output.json` and `data/output.csv` if data has changed
- Creates a zipped archive of results

### Dependencies Required
- `jq` - JSON processor for parsing API responses
- `curl` - HTTP client for API calls  
- `zip` - Compression utility

Install on Ubuntu/Debian:
```bash
sudo apt-get install jq curl zip
```

Install on macOS:
```bash
brew install jq curl zip
```

## Architecture

### Data Flow
1. **Data Fetching**: `scripts/get_zipped.sh` calls OpenRouter API endpoint
2. **Data Processing**: JSON response is converted to CSV with specific fields (id, name, created, context_length, pricing.prompt, pricing.completion)
3. **Data Storage**: Processed data stored in `data/` directory with timestamp tracking
4. **Presentation**: `index.html` reads CSV data and displays it using DataTables library
5. **Automation**: GitHub Actions workflow (`daily_run.yml`) runs twice daily at midnight and noon UTC

### Key Components

- **scripts/get_zipped.sh**: Core data fetching and processing script
  - Creates timestamped output directories
  - Compares new data with existing to avoid unnecessary updates
  - Maintains `data/updated` timestamp file for tracking last update

- **index.html**: Frontend display using DataTables
  - Dynamically loads CSV data from `data/output.csv`
  - Provides search, sort, pagination, and export capabilities
  - Shows last update timestamp from `data/updated`

- **.github/workflows/daily_run.yml**: Automation workflow
  - Scheduled runs at 00:00 and 12:00 UTC
  - Commits changes only when data has changed
  - Uploads zipped results as GitHub Actions artifacts

### Data Format

The project tracks these model fields:
- Model ID (unique identifier)
- Model Name (display name)
- Created Date (in YYYY-MM-DD format)
- Context Length (maximum token context)
- Prompt Cost (USD per 1M tokens)
- Completion Cost (USD per 1M tokens)

## Development Notes

- The project is designed to be maintenance-free with automatic updates
- All data updates are committed by the GitHub Actions bot
- The `results/` directory contains historical zipped snapshots
- The frontend uses CDN-hosted libraries (jQuery, DataTables) for simplicity
- GitHub Pages serves the static site directly from the main branch