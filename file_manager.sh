#!/usr/bin/env bash
# Batch File Renamer and Organizer
# Preview-first Bash utility. No external dependencies beyond common Unix tools.

set -uo pipefail
shopt -s nullglob dotglob

VERSION="1.0.0"
ROOT="."
MATCH="*"
RENAME_PATTERN="{name}.{ext}"
ORGANIZE="none"
MODE="preview"
LOG_FILE=""
COUNTER_START=1
COUNTER_WIDTH=3
COUNTER=0
CHANGES=0
SKIPPED=0
ERRORS=0

usage() {
  cat <<'EOF'
Batch File Renamer and Organizer

Usage:
  ./file_manager.sh [options]

Options:
  -d, --dir DIR              Directory to process (default: .)
  -m, --match GLOB           Shell glob for source files (default: *)
  -r, --rename-pattern TEXT  Output template (default: {name}.{ext})
  -o, --organize MODE        none | extension | date
  -l, --log FILE             TSV log path (default: DIR/rename_log.tsv)
      --counter-start N      First {counter} value (default: 1)
      --counter-width N      Zero-pad {counter} (default: 3)
      --apply                 Execute changes (preview is the default)
  -h, --help                 Show this help

Template tokens:
  {name}       Original filename without its final extension
  {ext}        Original extension without the dot
  {date}       File modification date (YYYY-MM-DD)
  {counter}    Sequential counter (zero-padded)

Examples:
  ./file_manager.sh --dir ./sample --match '*.txt' --rename-pattern 'doc_{counter}_{name}.{ext}'
  ./file_manager.sh --dir ./Downloads --organize extension
  ./file_manager.sh --dir ./Photos --organize date --apply
  ./file_manager.sh --dir ./data --match 'IMG_*' --rename-pattern '{date}_{name}.{ext}' --apply

Safety:
  Preview is the default. Use --apply to move files.
  Existing destinations and duplicate planned destinations are never overwritten.
  Invalid filename characters are replaced with underscores.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    -d|--dir) (($# >= 2)) || die "Missing value for $1"; ROOT=$2; shift 2 ;;
    -m|--match) (($# >= 2)) || die "Missing value for $1"; MATCH=$2; shift 2 ;;
    -r|--rename-pattern) (($# >= 2)) || die "Missing value for $1"; RENAME_PATTERN=$2; shift 2 ;;
    -o|--organize) (($# >= 2)) || die "Missing value for $1"; ORGANIZE=$2; shift 2 ;;
    -l|--log) (($# >= 2)) || die "Missing value for $1"; LOG_FILE=$2; shift 2 ;;
    --counter-start) (($# >= 2)) || die "Missing value for $1"; COUNTER_START=$2; shift 2 ;;
    --counter-width) (($# >= 2)) || die "Missing value for $1"; COUNTER_WIDTH=$2; shift 2 ;;
    --apply) MODE="apply"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

[[ -d "$ROOT" ]] || die "Directory does not exist: $ROOT"
[[ "$ORGANIZE" == "none" || "$ORGANIZE" == "extension" || "$ORGANIZE" == "date" ]] || die "Organize mode must be none, extension, or date"
[[ "$COUNTER_START" =~ ^[0-9]+$ && "$COUNTER_WIDTH" =~ ^[0-9]+$ ]] || die "Counter values must be non-negative integers"
(( COUNTER_WIDTH <= 12 )) || die "Counter width must be 12 or less"
ROOT=$(cd "$ROOT" && pwd -P)
[[ -n "$LOG_FILE" ]] || LOG_FILE="$ROOT/rename_log.tsv"
if [[ "$LOG_FILE" != /* ]]; then LOG_FILE="$ROOT/$LOG_FILE"; fi

# A tab-separated log is intentionally append-only. Escape tabs/newlines in fields.
log_field() { local value=$1; value=${value//$'\t'/ }; value=${value//$'\n'/ }; printf '%s' "$value"; }

# Replace template tokens without eval (so filenames are never executed as code).
render_template() {
  local template=$1 name=$2 ext=$3 file_date=$4 number=$5
  template=${template//\{name\}/$name}
  template=${template//\{ext\}/$ext}
  template=${template//\{date\}/$file_date}
  template=${template//\{counter\}/$number}
  printf '%s' "$template"
}

sanitize_name() {
  local value=$1
  # Characters invalid on common filesystems; slash is handled as a separator too.
  value=$(printf '%s' "$value" | LC_ALL=C tr '/\\:*?"<>|[:cntrl:]' '_')
  value=${value#" "}
  value=${value%" "}
  value=${value%.}
  [[ -n "$value" && "$value" != "." && "$value" != ".." ]] || value="renamed_file"
  printf '%s' "$value"
}

declare -a SOURCES=() TARGETS=() STATUSES=()
declare -A RESERVED=()
COUNTER=$COUNTER_START

# Top-level files only. Quoted glob expansion preserves spaces and special characters.
for source in "$ROOT"/$MATCH; do
  [[ -f "$source" ]] || continue
  [[ "$source" == "$LOG_FILE" ]] && continue
  base=$(basename -- "$source")
  parent=$(dirname -- "$source")
  if [[ "$base" == *.* && "$base" != .* ]]; then
    name=${base%.*}
    ext=${base##*.}
  else
    name=$base
    ext=""
  fi
  file_date=$(date -r "$source" '+%Y-%m-%d' 2>/dev/null) || file_date="unknown-date"
  number=$(printf "%0${COUNTER_WIDTH}d" "$COUNTER")
  COUNTER=$((COUNTER + 1))

  new_base=$(render_template "$RENAME_PATTERN" "$name" "$ext" "$file_date" "$number")
  new_base=$(sanitize_name "$new_base")
  destination_dir=$parent

  case "$ORGANIZE" in
    extension)
      folder=${ext,,}
      [[ -n "$folder" ]] || folder="no_extension"
      destination_dir="$ROOT/$folder"
      ;;
    date)
      [[ "$file_date" == "unknown-date" ]] && folder="unknown-date" || folder=${file_date:0:7}
      destination_dir="$ROOT/$folder"
      ;;
  esac

  target="$destination_dir/$new_base"
  SOURCES+=("$source")
  TARGETS+=("$target")
  STATUSES+=("READY")
done

if (("${#SOURCES[@]}" == 0)); then
  printf 'No files matched pattern: %s\n' "$MATCH"
  exit 0
fi

# First pass: validate every planned destination before moving anything.
for i in "${!SOURCES[@]}"; do
  source=${SOURCES[$i]}
  target=${TARGETS[$i]}
  status="READY"
  if [[ "$source" == "$target" ]]; then
    status="UNCHANGED"
  elif [[ -n "${RESERVED[$target]+x}" ]]; then
    status="COLLISION (duplicate target)"
  else
    RESERVED[$target]=$i
    # Existing paths are always treated as collisions. This deliberately avoids
    # order-dependent swaps and guarantees that a later mv cannot overwrite data.
    if [[ ( -e "$target" || -L "$target" ) && "$target" != "$source" ]]; then
      status="COLLISION (destination exists)"
    fi
  fi
  STATUSES[$i]=$status
done

printf '\nBatch File Renamer and Organizer v%s\n' "$VERSION"
printf 'Directory : %s\nPattern   : %s\nOrganize  : %s\nMode      : %s\n\n' "$ROOT" "$MATCH" "$ORGANIZE" "$MODE"
printf '%-34s -> %-34s %s\n' "OLD NAME" "NEW LOCATION / NAME" "STATUS"
printf '%s\n' '------------------------------------------------------------------------------------------------'

for i in "${!SOURCES[@]}"; do
  printf '%-34s -> %-34s %s\n' "$(basename -- "${SOURCES[$i]}")" "${TARGETS[$i]#"$ROOT"/}" "${STATUSES[$i]}"
  [[ "${STATUSES[$i]}" == READY ]] && CHANGES=$((CHANGES + 1)) || SKIPPED=$((SKIPPED + 1))
done

printf '\nSummary: %d planned, %d unchanged/collisions.\n' "$CHANGES" "$SKIPPED"
if [[ "$MODE" != "apply" ]]; then
  printf 'PREVIEW ONLY: no files were changed. Re-run with --apply to execute.\n'
  exit 0
fi

# Apply only after the complete plan has been displayed and validated.
[[ -e "$LOG_FILE" ]] || printf 'timestamp\told_path\tnew_path\tstatus\n' > "$LOG_FILE" || die "Cannot create log: $LOG_FILE"
timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')

for i in "${!SOURCES[@]}"; do
  [[ "${STATUSES[$i]}" == READY ]] || continue
  source=${SOURCES[$i]}
  target=${TARGETS[$i]}
  target_dir=$(dirname -- "$target")
  mkdir -p -- "$target_dir" || { printf 'FAILED\t%s\n' "$source" >&2; ERRORS=$((ERRORS + 1)); continue; }
  # Re-check immediately before mv to avoid clobbering a file created after preview.
  if [[ -e "$target" || -L "$target" ]]; then
    printf 'COLLISION\t%s\n' "$target" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi
  if mv -- "$source" "$target"; then
    printf '%s\t%s\t%s\tSUCCESS\n' "$(log_field "$timestamp")" "$(log_field "$source")" "$(log_field "$target")" >> "$LOG_FILE"
    printf 'MOVED: %s -> %s\n' "$source" "$target"
  else
    printf '%s\t%s\t%s\tFAILED\n' "$(log_field "$timestamp")" "$(log_field "$source")" "$(log_field "$target")" >> "$LOG_FILE"
    ERRORS=$((ERRORS + 1))
  fi
done

printf '\nCompleted with %d error(s). Log: %s\n' "$ERRORS" "$LOG_FILE"
(( ERRORS == 0 ))
