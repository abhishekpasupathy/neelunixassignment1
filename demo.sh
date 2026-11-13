#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/inbox"
printf 'Unix assignment notes\n' > "$WORK_DIR/inbox/class notes.txt"
printf 'Project report\n' > "$WORK_DIR/inbox/final report.pdf"
printf 'Photo data\n' > "$WORK_DIR/inbox/photo 01.jpg"

echo "1) Preview matching text files:"
"$SCRIPT_DIR/file_manager.sh" --dir "$WORK_DIR/inbox" --match '*.txt' --rename-pattern 'student_{counter}_{name}.{ext}'

echo
echo "2) Apply the rename:"
"$SCRIPT_DIR/file_manager.sh" --dir "$WORK_DIR/inbox" --match '*.txt' --rename-pattern 'student_{counter}_{name}.{ext}' --apply

echo
echo "3) Preview organizing remaining files by extension:"
"$SCRIPT_DIR/file_manager.sh" --dir "$WORK_DIR/inbox" --organize extension

echo
echo "4) Apply extension organization:"
"$SCRIPT_DIR/file_manager.sh" --dir "$WORK_DIR/inbox" --organize extension --apply

echo
echo "5) Resulting files:"
find "$WORK_DIR/inbox" -maxdepth 2 -type f -print | sort
echo
echo "6) Rename log:"
cat "$WORK_DIR/inbox/rename_log.tsv"
