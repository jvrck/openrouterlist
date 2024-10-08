#!/bin/bash
set -e

# Check if data/output.json exists, if not create it
# This will be run only once when the script is first executed
if [ ! -f "data/output.json" ]; then
    mkdir -p data
    touch "data/output.json"
fi

# Get the current timestamp
timestamp=$(date +"%Y%m%d_%H%M%S")

# Create a new directory inside the 'results' folder based on the timestamp
output_dir="results/output_$timestamp"
mkdir -p "$output_dir"

# Fetch the new data and save as output.json in the new directory
curl -X 'GET' \
    'https://openrouter.ai/api/v1/models' \
    -H 'accept: application/json' \
    -o "$output_dir/output.json"

# Add headers and convert JSON to CSV, saving to the new directory
echo "id,name,created,context_length,pricing.prompt,pricing.completion" > "$output_dir/output.csv"
jq -r '.data[] | [.id, .name, .created, .context_length, .pricing.prompt, .pricing.completion] | @csv' "$output_dir/output.json" >> "$output_dir/output.csv"

# Check if there is an existing output.json in the data directory
if [ -f "data/output.json" ]; then
    # Compare the newly fetched data with the existing data
    if cmp -s "$output_dir/output.json" "data/output.json"; then
        echo "No change in data, skipping update."
    else
        echo "Data has changed, updating files."

        cp "$output_dir/output.json" "data/output.json"
        cp "$output_dir/output.csv" "data/output.csv"
        echo "Copied output.json and output.csv to the data directory"

        # Output the timestamp to a file named updated only if there was a change in data
        echo "$timestamp" > ./data/updated
    fi
fi

# Print the output directory for reference
echo "Results saved in: $output_dir"

# Compress the output directory into a zip file
zip_file="results/output_$timestamp.zip"
zip -r "$zip_file" "$output_dir"

# Delete the output directory after zipping
rm -rf "$output_dir"
# Print the location of the zip file
echo "Zipped results saved in: $zip_file"

