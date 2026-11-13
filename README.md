# Batch File Renamer and Organizer

A safe, preview-first Unix assignment implemented in **Bash**. It renames files matching a configurable shell glob and optionally organizes them into folders by extension or modification date.

## Assignment coverage

| Requirement | Implementation |
|---|---|
| Configurable file matching | `--match '*.txt'` (shell globbing) |
| Configurable renaming | `--rename-pattern` with `{name}`, `{ext}`, `{date}`, `{counter}` tokens |
| Organize by extension | `--organize extension` creates folders such as `pdf/`, `txt/` |
| Organize by date | `--organize date` creates `YYYY-MM/` folders using modification time |
| Preview mode | Default mode; no files are changed unless `--apply` is supplied |
| Collision detection | Detects duplicate planned destinations and destinations that already exist |
| Invalid-character handling | Replaces common invalid filename characters and control characters with underscores |
| Old/new filename log | Appends successful and failed operations to a tab-separated log |
| Required Unix concepts | Globbing, parameter expansion, `basename`, `dirname`, `case`, loops, quoting and `mv` |

## Requirements

- Linux, macOS, or another Unix-like environment
- Bash 4.0 or newer
- Standard utilities: `basename`, `dirname`, `date`, `tr`, `mkdir`, and `mv`

No package installation is required.

## Quick start

```bash
chmod +x file_manager.sh
./file_manager.sh --help
```

Preview all text files in a folder and add a sequence number:

```bash
./file_manager.sh --dir ./sample --match '*.txt' --rename-pattern 'doc_{counter}_{name}.{ext}'
```

After checking the preview, execute it:

```bash
./file_manager.sh --dir ./sample --match '*.txt' --rename-pattern 'doc_{counter}_{name}.{ext}' --apply
```

## Usage

```text
./file_manager.sh [options]

-d, --dir DIR              Directory to process (default: current directory)
-m, --match GLOB           File glob (default: *)
-r, --rename-pattern TEXT  New filename template
-o, --organize MODE        none | extension | date
-l, --log FILE             Log file path
    --counter-start N      First counter value (default: 1)
    --counter-width N      Counter zero-padding (default: 3)
    --apply                 Apply the plan; without it, preview only
-h, --help                 Print help
```

### Template tokens

| Token | Meaning | Example |
|---|---|---|
| `{name}` | Original filename without its final extension | `report` |
| `{ext}` | Original extension without the dot | `pdf` |
| `{date}` | File modification date | `2026-11-13` |
| `{counter}` | Sequential, zero-padded counter | `001` |

The extension token is empty for files without an extension. A template such as `{date}_{name}.{ext}` therefore produces a trailing dot for extensionless files; the sanitization step removes trailing dots.

### Organization modes

- `none`: keep files in their current directory.
- `extension`: place files in a folder named after their extension. Files without an extension go into `no_extension/`.
- `date`: place files in a `YYYY-MM/` folder based on their last modification date. If the date cannot be read, use `unknown-date/`.

The organizer scans only the selected directory's top level; it does not recursively traverse subdirectories. This avoids accidentally processing files already placed into destination folders.

## Safety and collision policy

1. Preview is the default. No rename or move happens without `--apply`.
2. The complete proposed batch is displayed before execution.
3. Duplicate target paths within the batch are marked as collisions.
4. A target that already exists is marked as a collision; it is never overwritten.
5. Each destination is checked again immediately before `mv` to reduce race-related overwrites.
6. Invalid characters common to Unix/Windows-compatible filenames (including slash, backslash, colon, wildcard and control characters) are replaced with underscores.
7. Paths and filenames are quoted, so spaces and most shell-special characters are handled as data rather than split into multiple arguments.
8. The script does not delete files.

A preview is a plan, not a lock on the filesystem. Avoid running another process that changes the same directory between preview and apply. The script rechecks destinations before each move.

## Log format

The default log is `rename_log.tsv` inside the selected directory. It is append-only and contains:

```text
timestamp    old_path    new_path    status
```

A row is written for each attempted move. Successful operations are marked `SUCCESS`; failed moves are marked `FAILED`. Preview runs do not write to the log.

To choose another log path:

```bash
./file_manager.sh --dir ./sample --organize extension --log ./activity.tsv --apply
```

## Demonstration commands

Create a safe test directory:

```bash
mkdir -p sample
printf 'notes' > 'sample/my notes.txt'
printf 'report' > 'sample/final report.pdf'
printf 'image' > 'sample/photo 01.jpg'
```

Preview a rename:

```bash
./file_manager.sh --dir sample --match '*.txt' --rename-pattern 'college_{counter}_{name}.{ext}'
```

Apply it:

```bash
./file_manager.sh --dir sample --match '*.txt' --rename-pattern 'college_{counter}_{name}.{ext}' --apply
```

Preview extension organization:

```bash
./file_manager.sh --dir sample --organize extension
```

Apply extension organization:

```bash
./file_manager.sh --dir sample --organize extension --apply
```

For date organization, use `--organize date` instead.

## Test suite

Run the included tests:

```bash
chmod +x file_manager.sh test_file_manager.sh
./test_file_manager.sh
```

The tests use a temporary directory and verify preview safety, actual renaming, extension organization, collision handling, and log creation. Test files are removed automatically when the test finishes.

## How the Bash concepts are used

- **Globbing:** `"$ROOT"/$MATCH` expands the configured file pattern.
- **Parameter expansion:** `${base%.*}`, `${base##*.}`, and template substitutions split names and construct new names.
- **basename / dirname:** separate the filename from its parent directory.
- **case:** validates the organization mode and selects the correct destination folder.
- **Loops:** iterate through matched files, validate the complete plan, and apply it.
- **Quoting:** variables containing paths and filenames are quoted to preserve spaces and special characters.
- **mv:** performs the final file rename or move after validation.

## Suggested viva explanation

This Bash program automates bulk file renaming and organization. It accepts a directory, a shell wildcard pattern, a rename template, and an optional organization mode. It scans matching files, separates each filename into its name and extension, reads the modification date, generates a new filename using configurable tokens, and sanitizes invalid characters. Before changing anything, it displays a preview and checks for duplicate or already-existing destinations. The program changes files only when the user supplies `--apply`; it then creates the required folders, moves files with `mv`, and records old paths, new paths, timestamps, and operation status in a TSV log. This makes the operation predictable and prevents accidental overwrites.

## Learning outcomes / mapping

- **CO2, CO3, CO5:** applying shell scripting, filesystem operations, and safe automation.
- **PO2, PO3, PO5:** problem analysis, solution design, and use of Unix command-line tools.
- **SDG 9:** practical automation that improves digital infrastructure and productivity.
- **SDG 12:** organized file storage and reduced duplication / unnecessary rework.

## Limitations

- Top-level files only; recursive traversal is intentionally not enabled.
- Date organization uses modification date, not EXIF or creation metadata.
- The script uses Bash 4+ features (associative arrays and lowercase parameter expansion).
- It does not overwrite existing files or attempt complex multi-file swap operations.
