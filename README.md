# OpenRouter Model Information and Pricing

This project retrieves model information and pricing from OpenRouter's API, processes the data into CSV and JSON formats, and then generates an HTML page displaying the information in a table. The table is updated every 12 hours via a GitHub Action workflow.

## Features

- Fetches model data from the OpenRouter API.
- Converts the API response from JSON to CSV.
- Displays model information and pricing in an HTML table with search, export, and responsive features.
- Automatically updates the data twice daily using a GitHub Actions workflow.

## Files

- `scripts/get_zipped.sh`: A script that fetches model data from OpenRouter's API, converts it to CSV, and compresses the results into a zip file.
- `index.html`: Displays the retrieved model information and pricing in a table. It uses DataTables for pagination, search, and exporting options.
- `.github/workflows/daily_run.yml`: A GitHub Actions workflow that runs `get_zipped.sh` twice a day, commits updated data to the repository, and uploads the compressed results as an artifact.

## Setup

1. Clone the repository:
    ```bash
    git clone https://github.com/yourusername/openrouterlist.git
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

## GitHub Actions

This project is configured to automatically update the data every 12 hours using GitHub Actions:

- The workflow defined in `daily_run.yml` runs at midnight and noon UTC every day.
- It fetches the latest data, processes it, and commits any changes to the repository.
- The output is also zipped and uploaded as an artifact for easy access.

## Viewing the Results

The `index.html` page provides a table view of the data. To view it locally:

1. Open `index.html` in a web browser.
2. The table includes the following fields:
    - **Model ID**
    - **Model Name**
    - **Created Date** (in `YYYY-MM-DD` format)
    - **Context Length**
    - **Prompt Cost** (in USD per 1M tokens)
    - **Completion Cost** (in USD per 1M tokens)
   
   You can also export the table as CSV, Excel, PDF, or print it using the built-in buttons.

## Viewing Online

You can view the latest version of the table online via GitHub Pages:

[https://jvrck.github.io/openrouterlist/](https://jvrck.github.io/openrouterlist/)

This page is automatically updated with the latest model information and pricing data every 12 hours.

## License

This project is licensed under the MIT License.
