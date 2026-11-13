#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TOOL="$SCRIPT_DIR/file_manager.sh"
PASS=0
FAIL=0

check() {
  local description=$1
  shift
  if "$@"; then printf 'PASS: %s\n' "$description"; PASS=$((PASS + 1))
  else printf 'FAIL: %s\n' "$description"; FAIL=$((FAIL + 1)); fi
}

mkdir -p "$TMP/work"
printf 'alpha\n' > "$TMP/work/first notes.txt"
printf 'beta\n' > "$TMP/work/second notes.txt"

# Preview must not change source files.
"$TOOL" --dir "$TMP/work" --match '*.txt' --rename-pattern 'renamed_{counter}_{name}.{ext}' > "$TMP/preview.txt"
check "preview leaves original file untouched" test -f "$TMP/work/first notes.txt"
check "preview shows proposed filename" grep -q 'renamed_001_first notes.txt' "$TMP/preview.txt"

# Apply rename and verify the append-only log.
"$TOOL" --dir "$TMP/work" --match '*.txt' --rename-pattern 'renamed_{counter}_{name}.{ext}' --apply > "$TMP/apply.txt"
check "apply renames matching files" test -f "$TMP/work/renamed_001_first notes.txt"
check "log records old and new paths" grep -q 'SUCCESS' "$TMP/work/rename_log.tsv"

# Extension organization.
"$TOOL" --dir "$TMP/work" --organize extension --apply > "$TMP/organize.txt"
check "extension organizer creates txt folder" test -d "$TMP/work/txt"
check "extension organizer moves file" test -f "$TMP/work/txt/renamed_001_first notes.txt"

# Existing destination must be reported and not overwritten.
mkdir -p "$TMP/collision"
printf 'source' > "$TMP/collision/source.txt"
printf 'keep' > "$TMP/collision/target.txt"
"$TOOL" --dir "$TMP/collision" --match 'source.txt' --rename-pattern 'target.{ext}' > "$TMP/collision.txt"
check "collision is detected" grep -q 'COLLISION' "$TMP/collision.txt"
check "existing destination remains unchanged" grep -q 'keep' "$TMP/collision/target.txt"
check "collision source remains unchanged" test -f "$TMP/collision/source.txt"

# Invalid-character sanitization (colon is valid on Linux but not on common target filesystems).
mkdir -p "$TMP/invalid"
printf 'safe data' > "$TMP/invalid/bad:name.txt"
"$TOOL" --dir "$TMP/invalid" --match '*.txt' --apply > "$TMP/invalid-output.txt"
check "invalid filename characters are replaced" test -f "$TMP/invalid/bad_name.txt"

# Date organization uses the file modification month.
mkdir -p "$TMP/date"
printf 'dated data' > "$TMP/date/dated.txt"
DATE_FOLDER=$(date -r "$TMP/date/dated.txt" '+%Y-%m' 2>/dev/null || date '+%Y-%m')
"$TOOL" --dir "$TMP/date" --organize date --apply > "$TMP/date-output.txt"
check "date organizer creates a YYYY-MM folder" test -d "$TMP/date/$DATE_FOLDER"
check "date organizer moves file into its month folder" test -f "$TMP/date/$DATE_FOLDER/dated.txt"

printf '\nTests: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
