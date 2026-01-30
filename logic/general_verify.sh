#!/bin/bash
# Verifies integrity of OGG, Opus, M4A, WAV, etc. using ffmpeg.
# Excludes FLAC and MP3 as they have dedicated tools in this suite.

set -e
set -o pipefail

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/parallel.sh"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/lock.sh"

ROOT="."
JOBS="${DEFAULT_JOBS:-$(nproc 2>/dev/null || echo 4)}"
LOG="${LOG_DIRECTORY}/general_failures_$(date +%Y%m%d_%H%M%S).log"
RESUME=0
VERIFIED_LOG="${STATE_DIRECTORY}/general_verified_cache"
VERIFIED_LOCK="/tmp/general_verified_$$.lock"

usage() {
    log_usage "Usage: $(basename "$0") [OPTIONS] [directory]" "

Verifies integrity of OGG, Opus, M4A, WAV, and AIFF files using ffmpeg.

OPTIONS:
  -r, --resume-from-crash   Resume mode - skip previously verified files
  -j JOBS   Number of parallel jobs (default: nproc)
  -h        Show this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -j) JOBS="$2"; shift 2 ;;
        -r|--resume-from-crash) RESUME=1; shift ;;
        -h|--help) usage ;;
        *) ROOT="$1"; shift ;;
    esac
done

if [[ ! -d "$ROOT" ]]; then
    echo "Error: Directory '$ROOT' not found."
    exit 1
fi

# Resolve ROOT to absolute path for consistent caching
ROOT="$(cd "$ROOT" && pwd)"

# Check for ffmpeg
if ! command -v ffmpeg >/dev/null 2>&1; then
    log_error "ffmpeg is required for this script but was not found."
    exit 1
fi

log_header "Scanning for OGG, Opus, M4A, WAV, AIFF files..."

# Find files matching extensions (case insensitive)
mapfile -t files_to_check < <(find "$ROOT" -type f \( \
    -iname '*.ogg' -o \
    -iname '*.opus' -o \
    -iname '*.m4a' -o \
    -iname '*.wav' -o \
    -iname '*.aiff' -o \
    -iname '*.wma' \
    \) | sort)

TOTAL_FILES=${#files_to_check[@]}

if [[ $TOTAL_FILES -eq 0 ]]; then
    log_info "No matching audio files found in '$ROOT'."
    exit 0
fi

# Filter out already-verified files in resume mode
ALREADY_VERIFIED=0
if [[ "$RESUME" -eq 1 ]] && [[ -f "$VERIFIED_LOG" ]]; then
    ALREADY_VERIFIED=$(wc -l < "$VERIFIED_LOG" 2>/dev/null || echo 0)

    if [[ $ALREADY_VERIFIED -gt 0 ]]; then
        log_info "Resume mode: filtering $ALREADY_VERIFIED previously verified files..."

        mapfile -t files_to_check < <(comm -23 <(printf '%s\n' "${files_to_check[@]}" | sort) <(sort "$VERIFIED_LOG"))

        TOTAL_FILES=${#files_to_check[@]}
        log_info "Files remaining to verify: $TOTAL_FILES"
    fi
fi

# --- Worker Function ---
verify_worker() {
    local f="$1"
    local status_msg
    
    # Decode to null to check for stream errors
    # -v error: only show errors
    # -f null -: discard output
    if ffmpeg -v error -i "$f" -f null - 2>&1 | grep -q .; then
        status_msg="${COLOR_RED}❌ FAIL${COLOR_RESET}"
        # Log the specific error to the log file
        flock -x 200
        echo "---------------------------------------------------" >> "$LOG"
        echo "FILE: $f" >> "$LOG"
        ffmpeg -v error -i "$f" -f null - 2>&1 >> "$LOG"
    else
        status_msg="${COLOR_GREEN}✅ OK${COLOR_RESET}"
        # Log success to verified log
        {
            flock -x 201
            printf '%s\n' "$f" >> "$VERIFIED_LOG"
        } 201>"$VERIFIED_LOCK"
    fi

    local count=$(increment_counter)
    local total=$(get_total_items)
    local bar=$(get_progress_bar "$count" "$total" 10)

    print_status_row "$(basename "$f")" "$bar" "$status_msg"
}
export -f verify_worker
export LOG VERIFIED_LOG VERIFIED_LOCK

initialize_parallel "$TOTAL_FILES"

# Register our specific lock file for cleanup
register_temp_file "$VERIFIED_LOCK"

log_header "Verifying $TOTAL_FILES files using $JOBS jobs..."
printf "%-80s | %-18s | %s\n" "File" "Progress" "Status"
echo "----------------------------------------------------------------------------------------"

WORKER_CMD="source \"$SCRIPT_DIR/../lib/logging.sh\"; source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/config.sh\"; source \"$SCRIPT_DIR/../lib/lock.sh\"; source \"$SCRIPT_DIR/../lib/utils.sh\"; verify_worker \"\$0\""
printf '%s\0' "${files_to_check[@]}" | xargs -0 -n 1 -P "$JOBS" bash -c "$WORKER_CMD"

if [[ -f "$LOG" ]]; then
    log_error "Failures detected. See $LOG for details."
    exit 1
else
    log_success "All files verified successfully."
    exit 0
fi