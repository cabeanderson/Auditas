#!/bin/bash
# Scan for missing FLAC MD5s. Optionally fix them by re-encoding.
# Usage: music-suite md5 [--fix] [directory]

# Source the logging library first for immediate use
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"

set -e
set -o pipefail

MODE="scan"
DIR="."
ASSUME_YES=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)
            MODE="fix"
            shift
            ;;
        -j)
            JOBS="$2"
            shift 2
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        -h|--help)
            log_usage "Usage: $(basename "$0") [--fix] [directory]" "
  -j jobs Number of parallel jobs for fixing (default: nproc)
  -y      Assume yes to prompts (non-interactive)
  --fix   Re-encode files to fix missing MD5 checksums"
            exit 0
            ;;
        *)
            DIR="$1"
            shift
            ;;
    esac
done

if [[ ! -d "$DIR" ]]; then
    log_error "Directory '$DIR' not found."
    exit 1
fi

log_header "Scanning first tracks for missing MD5 in: $DIR"
if [[ "$MODE" == "fix" ]]; then
    log_warning "FIX MODE ENABLED: Files will be re-encoded and originals backed up."
else
    log_info "SCAN MODE: Reporting only. Use --fix to repair."
fi

# Find all albums with first tracks missing an MD5
mapfile -t albums_to_fix < <(find "$DIR" -type f \( -name '01*.flac' -o -name '01-*.flac' \) | sort | while read -r first_track; do
    md5=$(metaflac --show-md5sum "$first_track" 2>/dev/null)
    if [ -z "$md5" ] || [ "$md5" = "00000000000000000000000000000000" ]; then
        album_dir=$(dirname "$first_track")
        echo "$album_dir"
    fi
done)

if [ ${#albums_to_fix[@]} -eq 0 ]; then
    log_success "No albums with missing MD5s found."
    exit 0
fi

log_info "Found ${#albums_to_fix[@]} album(s) with missing MD5s."

if [[ "$MODE" == "scan" ]]; then
    log_info "Albums to fix:"
    printf "  - %s\n" "${albums_to_fix[@]}"
    echo
    log_info "Run with --fix to re-encode all files in these albums."
    exit 0
fi

# --- FIX MODE ---

# Collect all files from the identified albums
mapfile -t files_to_fix < <(for album_dir in "${albums_to_fix[@]}"; do
    find "$album_dir" -maxdepth 1 -type f -iname '*.flac'
done | sort -u)

TOTAL_FILES=${#files_to_fix[@]}
log_info "Found $TOTAL_FILES total files to re-encode."
if [[ "$ASSUME_YES" -eq 0 ]]; then
    log_prompt "Continue? [y/N]"
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_error "Aborting."
        exit 0
    fi
fi

# Source the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/parallel.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

# Define the worker function
fix_md5_file() {
    local f="$1"
    local album_dir
    album_dir=$(dirname "$f")
    local filename
    filename=$(basename "$f")
    local backup_dir="$album_dir/backup_md5"
    local temp_file="$album_dir/tmp_$filename"
    local status

    # Ensure backup dir exists (mkdir -p is atomic and safe in parallel)
    mkdir -p "$backup_dir"

    # Re-encode
    if flac -8 --verify --preserve-modtime "$f" -o "$temp_file" >/dev/null 2>&1; then
        # Verify bit-perfect audio by comparing decoded MD5 hashes
        old_md5=$(calculate_audio_hash "$f")
        new_md5=$(calculate_audio_hash "$temp_file")

        if [[ "$old_md5" == "$new_md5" ]]; then
            mv "$f" "$backup_dir/"
            mv "$temp_file" "$f"
            status="${COLOR_GREEN}✅ Fixed${COLOR_RESET}"
        else
            status="${COLOR_RED}❌ FAIL (hash mismatch)${COLOR_RESET}"
            rm -f "$temp_file"
        fi
    else
        status="${COLOR_RED}❌ FAIL (re-encode)${COLOR_RESET}"
        rm -f "$temp_file"
    fi

    local count
    count=$(increment_counter)
    local total
    total=$(get_total_items)

    local bar
    bar=$(get_progress_bar "$count" "$total" 10)
    print_status_row "$f" "$bar" "$status"
}
export -f fix_md5_file

# Initialize and run
initialize_parallel "$TOTAL_FILES"

log_header "Re-encoding $TOTAL_FILES files across ${#albums_to_fix[@]} albums using $JOBS jobs..."
printf "%-80s | %-18s | %s\n" "File" "Progress" "Status"
echo "---------------------------------------------------------------------------------------------"

# Construct the worker command string, explicitly sourcing libraries to ensure functions are available
WORKER_CMD="source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/utils.sh\"; fix_md5_file \"\$0\""

printf '%s\0' "${files_to_fix[@]}" | xargs -0 -n 1 -P "$JOBS" bash -c "$WORKER_CMD"

log_header "Repairs complete."
log_info "Original files are in 'backup_md5' folders within each album directory."