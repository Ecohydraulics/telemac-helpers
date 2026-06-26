#!/usr/bin/env bash
#
# Copyright (C) 2026 Sebastian Schwindt
#
# This script is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or, at your
# option, any later version.
#
# This script is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# WARNING:
# This script may install system packages, download third-party source code,
# compile software, create symbolic links, and modify user-level desktop/menu
# entries. Review the script before running it. Use it at your own risk.
# Do not run it on production, shared, institutional, or safety-critical
# systems unless you have authorization, backups, and a tested recovery plan.
#
# CONTENT:
# This script finds and renames any files or directories containing spaces by replacing them with dashes.
# It operates recursively starting from a chosen directory (or the current directory if none is provided).

cat <<'EOF'
This installer is provided without warranty.

It may corrupt third-party code, software,
create symlinks, and desktop/menu entries. Review the
script before continuing. Use at your own risk.

EOF

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

