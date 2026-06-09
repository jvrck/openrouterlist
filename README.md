# OpenRouter Model Pricing Comparison Tool 🚀

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)
[![GitHub Actions](https://img.shields.io/badge/Updated-Every%2012%20Hours-blue.svg)](https://github.com/jvrck/openrouterlist/actions)
[![Website](https://img.shields.io/badge/Website-Live-brightgreen.svg)](https://openrouterlist.jvrck.com/)

A comprehensive, real-time pricing comparison tool for 400+ AI language models available through the [OpenRouter API](https://openrouter.ai/). Compare costs across GPT-4, Claude, Llama, Mistral, and hundreds of other models to find the most cost-effective solution for your AI needs.

**🔗 Live Tool: [https://openrouterlist.jvrck.com/](https://openrouterlist.jvrck.com/)**

## 📊 Key Features

- **Real-Time Pricing Data**: Automatically updated every 12 hours from OpenRouter's API
- **400+ AI Models**: Comprehensive coverage of all available models including GPT-4, Claude 3, Llama 3, and more
- **Advanced Filtering**: Filter by capabilities (tool calling, structured outputs, reasoning, web search)
- **Cost Calculator**: Pricing shown per million tokens for both prompts and completions
- **Price History & Trends**: Per-model price charts, 30-day change badges, and a searchable archive of discontinued models — backfilled from 20+ months of git history
- **Export Options**: Download data as CSV, Excel, PDF, or print for offline analysis
- **Dark Mode**: Eye-friendly dark theme for extended use
- **Mobile Responsive**: Optimized for all devices with card and table views

## 🔍 Use Cases

- **Developers**: Find the most cost-effective model for your application
- **Businesses**: Compare enterprise AI solution costs
- **Researchers**: Analyze pricing trends across different model families
- **Budget Planning**: Estimate token costs for your AI projects

## 📁 Project Structure

- `index.html` - Interactive web interface with advanced filtering and search
- `scripts/get_zipped.sh` - Data fetching script that pulls latest pricing from OpenRouter API
- `scripts/backfill_history.py` - Builds/maintains the price-history ledger (incremental daily; `--rebuild` walks full git history)
- `.github/workflows/daily_run.yml` - Automated GitHub Actions workflow for data updates
- `data/` - Current model pricing data in JSON and CSV formats
- `data/history/prices.json` - Compact per-model price-history ledger (change-points + first/last seen)
- `robots.txt` - Search engine crawler instructions
- `sitemap.xml` - Sitemap for better SEO indexing

## 🚀 Quick Start

1. Clone the repository:
    ```bash
    git clone https://github.com/jvrck/openrouterlist.git
    cd openrouterlist
    ```

2. Make sure you have `jq`, `curl`, and `zip` installed:
    ```bash
    sudo apt-get install jq curl zip
    ```

    On macOS:
    ```bash
    brew install jq curl zip
    ```

3. Run the script manually:
    ```bash
    bash ./scripts/get_zipped.sh
    ```

4. View the results in the `results` folder or on the `output.csv` and `output.json` files.

## 🤖 Automated Updates

The pricing data is automatically refreshed every 12 hours using GitHub Actions:

- Updates run at midnight and noon UTC daily
- Latest pricing data is fetched directly from OpenRouter's API
- Changes are automatically committed to the repository
- The price-history ledger (`data/history/prices.json`) is updated incrementally on every change
- Historical data is archived in timestamped zip files

## 📈 Data Fields

The comparison tool displays the following information for each model:

| Field | Description |
|-------|-------------|
| **Model ID** | Unique identifier for API calls |
| **Model Name** | Human-readable model name |
| **Created Date** | Model release date (YYYY-MM-DD) |
| **Context Length** | Maximum token context window |
| **Prompt Cost** | USD per 1M input tokens |
| **Completion Cost** | USD per 1M output tokens |
| **Tool Calling** | Supports function/API calls |
| **Structured Outputs** | Returns formatted JSON/XML |
| **Reasoning** | Shows step-by-step thinking |
| **Response Format** | Custom output formatting |
| **Web Search** | Can search the internet |

## 🌐 Live Website

Access the tool online: **[https://openrouterlist.jvrck.com/](https://openrouterlist.jvrck.com/)**

The website features:
- Real-time search and filtering
- Export to CSV, Excel, PDF
- Dark/light theme toggle
- Mobile-responsive design
- Keyboard shortcuts for power users
- Price-history charts and a discontinued-models archive

## 🤝 Contributing

Contributions are welcome! Feel free to:

- Report bugs or request features via [Issues](https://github.com/jvrck/openrouterlist/issues)
- Submit pull requests with improvements
- Share the tool with others who might find it useful

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Related Links

- [OpenRouter API](https://openrouter.ai/)
- [OpenRouter Documentation](https://openrouter.ai/docs)
- [API Pricing](https://openrouter.ai/docs#pricing)

---

**Keywords**: OpenRouter pricing, AI model costs, LLM pricing comparison, GPT-4 pricing, Claude pricing, Llama pricing, AI API costs, model comparison tool, token pricing calculator, language model costs, OpenRouter models
