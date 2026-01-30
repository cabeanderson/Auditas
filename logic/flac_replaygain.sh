#!/bin/bash
# Applies ReplayGain (R128) tags to FLAC files in parallel.

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

set -e
set -o pipefail

# --- Source Libraries ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/parallel.sh"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/lock.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

# --- Configuration ---
ROOT="."
JOBS="${DEFAULT_JOBS:-$(nproc 2>/dev/null || echo 4)}"
DRY_RUN=0
LOG_FILE="${LOG_DIRECTORY}/replaygain_errors_$(date +%Y%m%d_%H%M%S).log"
LOUDGAIN_TARGET="${REPLAYGAIN_TARGET:--18}"

# Tags to remove before re-analysis
TAGS_TO_REMOVE=(
    "REPLAYGAIN_TRACK_GAIN"
    "REPLAYGAIN_TRACK_PEAK"
    "REPLAYGAIN_ALBUM_GAIN"
    "REPLAYGAIN_ALBUM_PEAK"
    "REPLAYGAIN_REFERENCE_LOUDNESS"
    "REPLAYGAIN_ALBUM_RANGE"
    "REPLAYGAIN_TRACK_RANGE"
)

# --- Usage ---
usage() {
    log_usage "Usage: $(basename "$0") [OPTIONS] [path]" "

Applies ReplayGain tags to FLAC files, processing albums in parallel.

OPTIONS:
  -j JOBS       Number of parallel jobs (default: nproc)
  --dry-run     Scan and report what would be done, but do not modify files.
  -h, --help    Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j) JOBS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        *) ROOT="$1"; shift ;;
    esac
done

# --- Worker Function ---
process_album_worker() {
    album_root="$1"
    status_msg=""

    # Check if there are any files to process
    if ! find "$album_root" -maxdepth 1 -type f -name "*.flac" -print -quit | grep -q .; then
        exit 0
    fi

    mapfile -d $'\0' flac_files < <(find "$album_root" -maxdepth 1 -type f -name "*.flac" -print0)
    file_count=${#flac_files[@]}

    # Idempotency Check: Skip if already tagged correctly
    if metaflac --list --block-type=VORBIS_COMMENT "${flac_files[0]}" 2>/dev/null | grep -q "REPLAYGAIN_REFERENCE_LOUDNESS=${LOUDGAIN_TARGET}"; then
        status_msg="${COLOR_YELLOW}✓ SKIP (already tagged)${COLOR_RESET}"
    # Permission Check
    elif [[ ! -w "${flac_files[0]}" ]]; then
        status_msg="${COLOR_RED}✗ FAIL (permission denied)${COLOR_RESET}"
        ( flock -x 200; log_error "Permission denied on: $album_root" >> "$LOG_FILE"; ) 200>"${LOG_FILE}.lock"
    else
        # Remove old tags
        if [[ "$DRY_RUN" -eq 0 ]]; then
            for f in "${flac_files[@]}"; do
                for tag in "${TAGS_TO_REMOVE[@]}"; do
                    metaflac --remove-tag="$tag" "$f" &>/dev/null
                done
            done
        fi

        # Determine loudgain mode
        loudgain_options=("-s" "e" "-k") # Tag files, no-clip protection
        [[ $file_count -gt 1 ]] && loudgain_options+=("-a") # Album mode

        # Execute Loudgain
        if [[ "$DRY_RUN" -eq 0 ]]; then
            if ! loudgain "${loudgain_options[@]}" "${flac_files[@]}" &>/dev/null; then
                status_msg="${COLOR_RED}✗ FAIL (loudgain error)${COLOR_RESET}"
                (
                    flock -x 200
                    echo "---" >> "$LOG_FILE"
                    log_error "Loudgain failed on: $album_root" >> "$LOG_FILE"
                    # Re-run to capture error output
                    loudgain "${loudgain_options[@]}" "${flac_files[@]}" >> "$LOG_FILE" 2>&1
                ) 200>"${LOG_FILE}.lock"
            else
                status_msg="${COLOR_GREEN}✓ APPLIED${COLOR_RESET}"
            fi
        else
            status_msg="${COLOR_YELLOW}✓ DRY RUN${COLOR_RESET}"
        fi
    fi

    count=$(increment_counter)
    total=$(get_total_items)
    bar=$(get_progress_bar "$count" "$total" 10)
    display_name=$(truncate_path "$(basename "$album_root")" 45)
    # Strip any trailing carriage returns that can corrupt printf alignment
    display_name=${display_name%$'\r'}
    printf "%-45s | %-18s | %b\n" "$display_name" "$bar" "$status_msg"
}
export -f process_album_worker

# --- Main Logic ---
log_header "Scanning for albums to apply ReplayGain..."
[[ "$DRY_RUN" -eq 1 ]] && log_warning "DRY RUN MODE ENABLED. No files will be modified."

# Find all unique album directories
mapfile -t albums_to_process < <(find "$ROOT" -type f -iname '*.flac' -print0 | xargs -0 -n 1 dirname | sort -u)
TOTAL_ALBUMS=${#albums_to_process[@]}

if [[ $TOTAL_ALBUMS -eq 0 ]]; then
    log_info "No FLAC albums found to process."
    exit 0
fi

initialize_parallel "$TOTAL_ALBUMS"

log_header "Processing $TOTAL_ALBUMS albums using $JOBS jobs..."
printf "%-80s | %-18s | %s\n" "Album" "Progress" "Status"
echo "-----------------------------------------------------------------------------"

# Export variables needed by the worker script
export DRY_RUN LOG_FILE LOUDGAIN_TARGET
export -a TAGS_TO_REMOVE

# Construct the worker command string, explicitly sourcing libraries to ensure functions are available
WORKER_CMD="source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/utils.sh\"; process_album_worker \"\$0\""

printf '%s\0' "${albums_to_process[@]}" | xargs -0 -n 1 -P "$JOBS" bash -c "$WORKER_CMD"

log_header "ReplayGain processing complete."
if [[ -f "$LOG_FILE" ]]; then
    if [[ $(wc -l < "$LOG_FILE") -gt 0 ]]; then
        log_error "Failures detected. See $LOG_FILE for details."
        exit 1
    else
        rm -f "$LOG_FILE" "${LOG_FILE}.lock"
    fi
fi

log_success "All albums processed successfully."
exit 0