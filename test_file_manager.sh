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

# A glob containing a literal space must not be split into multiple patterns.
mkdir -p "$TMP/spaces"
printf 'match' > "$TMP/spaces/my report.txt"
printf 'ignore' > "$TMP/spaces/other.txt"
"$TOOL" --dir "$TMP/spaces" --match 'my *.txt' --rename-pattern 'found_{name}.{ext}' --apply > "$TMP/spaces-output.txt"
check "glob with a space matches the intended file" test -f "$TMP/spaces/found_my report.txt"
check "glob with a space leaves other files untouched" test -f "$TMP/spaces/other.txt"

# Default * must not match hidden files.
mkdir -p "$TMP/dotfiles"
printf 'hidden' > "$TMP/dotfiles/.gitignore"
printf 'visible' > "$TMP/dotfiles/visible.txt"
"$TOOL" --dir "$TMP/dotfiles" --organize extension --apply > "$TMP/dotfiles-output.txt"
check "default glob leaves dotfiles untouched" test -f "$TMP/dotfiles/.gitignore"

# Extension folders must sanitize special characters.
mkdir -p "$TMP/special-extension"
printf 'data' > "$TMP/special-extension/weird.a*b"
"$TOOL" --dir "$TMP/special-extension" --organize extension --apply > "$TMP/special-extension-output.txt"
check "special-character extension gets sanitized folder" test -f "$TMP/special-extension/a_b/weird.a_b"

# Two source files mapping to one destination must report a collision.
mkdir -p "$TMP/duplicate"
printf 'first' > "$TMP/duplicate/one.txt"
printf 'second' > "$TMP/duplicate/two.txt"
"$TOOL" --dir "$TMP/duplicate" --match '*.txt' --rename-pattern 'shared.{ext}' > "$TMP/duplicate-output.txt"
check "duplicate planned target reports COLLISION" grep -q 'COLLISION (duplicate target)' "$TMP/duplicate-output.txt"
check "duplicate-target preview leaves both sources untouched" test -f "$TMP/duplicate/two.txt"

printf '\nTests: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
