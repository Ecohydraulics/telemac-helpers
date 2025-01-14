#!/usr/bin/env bash

# This script finds and renames any files or directories containing spaces by replacing them with dashes.
# It operates recursively starting from a chosen directory (or the current directory if none is provided).

read -rp "Enter the directory path (leave blank for current directory): " ROOT_DIR
ROOT_DIR="${ROOT_DIR:-.}"

echo "Scanning '$ROOT_DIR' and replacing spaces with dashes..."

find "$ROOT_DIR" -depth -name "* *" | while IFS= read -r entry; do
    parent_dir="$(dirname "$entry")"
    base_name="$(basename "$entry")"
    new_name="${base_name// /-}"
    new_path="$parent_dir/$new_name"

    if [[ "$entry" != "$new_path" ]]; then
        mv "$entry" "$new_path"
        echo "Renamed: $entry -> $new_path"
    fi
done

echo "Done!"

