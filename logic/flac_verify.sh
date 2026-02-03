#!/bin/bash
# FLAC integrity checker with optional ffmpeg decode, parallelized.
# Enhanced version with progress tracking, resume capability, and detailed error reporting.
set -e
set -o pipefail

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/parallel.sh"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/lock.sh"

# ---------------- Configuration ----------------
ROOT="."
JOBS="${DEFAULT_JOBS:-$(nproc 2>/dev/null || echo 4)}"
USE_FFMPEG=0
CHECK_MD5=1
RESUME=0
LOG="${LOG_DIRECTORY}/flac_failures_$(date +%Y%m%d_%H%M%S).log"
MD5_REPORT="${LOG_DIRECTORY}/flac_missing_md5_$(date +%Y%m%d_%H%M%S).log"
VERIFIED_LOG="${STATE_DIRECTORY}/verified.log"
LOG_LOCK="/tmp/flac_log_$$.lock"
VERIFIED_LOCK="/tmp/flac_verified_$$.lock"
MD5_LOCK="/tmp/flac_md5_$$.lock"

# ---------------- Usage ----------------
usage() {
    log_usage "Usage: auditas verify [OPTIONS] [path]" "

FLAC file verification tool with parallel processing and resume capability.

OPTIONS:
  -f              Enable ffmpeg full decode check
  -j jobs         Number of parallel jobs (default: nproc)
  -r, --resume    Resume mode - skip previously verified files
  -m, --no-md5    Disable MD5 missing check (enabled by default)
  --clear-cache   Clear verification cache and start fresh
  -h, --help      Show this help message

ARGUMENTS:
  path            Root directory to scan (default: current directory)

EXAMPLES:
  $0 /music                    # Verify all FLAC files in /music
  $0 -f -j 8 /music           # Use 8 threads with ffmpeg checking
  $0 -r /music                # Resume previous verification
  $0 --no-md5 /music          # Skip MD5 missing check
  $0 --clear-cache            # Clear cache and exit
"
    exit 1
}

# ---------------- Argument parsing ----------------
CLEAR_CACHE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            USE_FFMPEG=1
            shift
            ;;
        -j)
            JOBS="$2"
            shift 2
            ;;
        -r|--resume)
            RESUME=1
            shift
            ;;
        -m|--no-md5)
            CHECK_MD5=0
            shift
            ;;
        --clear-cache)
            CLEAR_CACHE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            ROOT="$1"
            shift
            ;;
    esac
done

# Handle cache clearing
if [[ $CLEAR_CACHE -eq 1 ]]; then
    if [[ -f "$VERIFIED_LOG" ]]; then
        rm -f "$VERIFIED_LOG"
        log_success "Verification cache cleared."
    else
        log_info "No cache file found."
    fi
    exit 0
fi

# Validate jobs count
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || JOBS="$(nproc 2>/dev/null || echo 4)"

# Validate root directory
if [[ ! -d "$ROOT" ]]; then
    log_error "Directory '$ROOT' does not exist."
    exit 1
fi

# Resolve ROOT to absolute path for consistent caching
ROOT="$(cd "$ROOT" && pwd)"

# Export variables for worker function
export USE_FFMPEG LOG VERIFIED_LOG RESUME ROOT CHECK_MD5 MD5_REPORT
export LOG_LOCK VERIFIED_LOCK MD5_LOCK

# ---------------- Worker function ----------------
check_file() {
    local f="$1"
    local dir file status_msg fail=0 error_detail=""
    local ts=$(date +%Y-%m-%dT%H:%M:%S)

    # Extract directory and filename
    local rel_path="${f#$ROOT/}"
    [[ "$rel_path" == "$f" ]] && rel_path="${f#./}"
    dir="${rel_path%/*}"
    [[ "$dir" == "$rel_path" ]] && dir="."
    file="${rel_path##*/}"

    # 1. FLAC integrity check
    local flac_err
    if ! flac_err=$(flac -t "$f" 2>&1); then
        status_msg="${COLOR_RED}❌ FAIL (flac)${COLOR_RESET}"
        # Extract error message after the colon, skip the filename part
        error_detail=$(echo "$flac_err" | grep -E "(ERROR|error|\*\*\*)" | sed 's/^[^:]*: //' | head -n1 | sed 's/^[[:space:]]*//')
        [[ -z "$error_detail" ]] && error_detail="Unknown FLAC error"
        {
            flock -x 200
            printf '%s | %s | %s | %s\n' "$ts" "FLAC_FAIL" "$f" "$error_detail" >> "$LOG"
        } 200>"$LOG_LOCK"
        fail=1
    # 2. Optional ffmpeg decode
    elif [[ "$USE_FFMPEG" -eq 1 ]]; then
        local ffmpeg_err
        if ! ffmpeg_err=$(ffmpeg -v error -i "$f" -f null - 2>&1); then
            status_msg="${COLOR_RED}❌ FAIL (ffmpeg)${COLOR_RESET}"
            # FFmpeg errors are usually cleaner, just trim whitespace
            error_detail=$(echo "$ffmpeg_err" | head -n1 | sed 's/^[[:space:]]*//')
            [[ -z "$error_detail" ]] && error_detail="Unknown FFmpeg error"
            {
                flock -x 200
                printf '%s | %s | %s | %s\n' "$ts" "FFMPEG_FAIL" "$f" "$error_detail" >> "$LOG"
            } 200>"$LOG_LOCK"
            fail=1
        fi
    fi

    # Mark as verified if successful
    if [[ $fail -eq 0 ]]; then
        status_msg="${COLOR_GREEN}✅ OK${COLOR_RESET}"
        {
            flock -x 201
            printf '%s\n' "$f" >> "$VERIFIED_LOG"
        } 201>"$VERIFIED_LOCK"

        # Check for missing MD5 if enabled
        if [[ "$CHECK_MD5" -eq 1 ]]; then
            if ! metaflac --show-md5sum "$f" 2>/dev/null | grep -qv '^00000000000000000000000000000000$'; then
                # MD5 is missing or all zeros - log the directory
                local folder_path="${f%/*}"
                {
                    flock -x 203
                    # Use a temp file to track unique folders
                    if ! grep -qxF "$folder_path" "$MD5_REPORT" 2>/dev/null; then
                        printf '%s\n' "$folder_path" >> "$MD5_REPORT"
                    fi
                } 203>"$MD5_LOCK"
            fi
        fi
    fi

    # Increment counter and get current/total counts
    local count
    count=$(increment_counter)
    local total
    total=$(get_total_items)

    local bar
    bar=$(get_progress_bar "$count" "$total" 10)

    print_status_row "$rel_path" "$bar" "$status_msg"
}
export -f check_file

# ---------------- Initialize parallel environment ----------------
# Note: initialize_parallel is called later after counting files, 
# but we can register locks now if we initialize with 0 first or just wait.
# Ideally, we wait to initialize until we have a count.

# ---------------- Count total files ----------------
log_header "Scanning for FLAC files..."
mapfile -t flac_files < <(find "$ROOT" -type f -iname '*.flac' 2>/dev/null)
TOTAL_FILES=${#flac_files[@]}

if [[ $TOTAL_FILES -eq 0 ]]; then
    log_info "No FLAC files found in '$ROOT'"
    exit 0
fi

# Initialize parallel processing environment
initialize_parallel "$TOTAL_FILES"

# Register lock files for automatic cleanup
register_temp_file "$LOG_LOCK"
register_temp_file "$VERIFIED_LOCK"
register_temp_file "$MD5_LOCK"

# Filter out already-verified files in resume mode (bulk operation)
ALREADY_VERIFIED=0
if [[ "$RESUME" -eq 1 ]] && [[ -f "$VERIFIED_LOG" ]]; then
    ALREADY_VERIFIED=$(wc -l < "$VERIFIED_LOG" 2>/dev/null || echo 0)

    if [[ $ALREADY_VERIFIED -gt 0 ]]; then
        log_info "Resume mode: filtering $ALREADY_VERIFIED previously verified files..."

        # Use comm to find files NOT in verified log (set difference)
        # comm -23: lines only in file1 (all files), not in file2 (verified)
        mapfile -t flac_files < <(comm -23 \
            <(printf '%s\n' "${flac_files[@]}" | sort) \
            <(sort "$VERIFIED_LOG"))

        TOTAL_FILES=${#flac_files[@]}
        initialize_parallel "$TOTAL_FILES" # Re-initialize with new total
        log_info "Files remaining to verify: $TOTAL_FILES"
    fi
fi

# ---------------- Header ----------------
log_header "FLAC Verification Report"
log_info "Root directory : $ROOT"
log_info "Total files    : $TOTAL_FILES"
[[ "$RESUME" -eq 1 ]] && log_info "Already verified: $ALREADY_VERIFIED (resume mode)"
log_info "Parallel jobs  : $JOBS"
log_info "ffmpeg check   : $([[ $USE_FFMPEG -eq 1 ]] && echo enabled || echo disabled)"
log_info "MD5 check      : $([[ $CHECK_MD5 -eq 1 ]] && echo enabled || echo disabled)"
[[ $CHECK_MD5 -eq 1 ]] && log_info "MD5 report     : $MD5_REPORT"
log_info "Failure log    : $LOG"
echo "---------------------------------------------------------------------------"
printf "%-80s | %-18s | %s\n" "File" "Progress" "Status"
echo "---------------------------------------------------------------------------"

# ---------------- Run ----------------
# Construct the worker command string, explicitly sourcing libraries to ensure functions are available
WORKER_CMD="source \"$SCRIPT_DIR/../lib/logging.sh\"; source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/utils.sh\"; check_file \"\$0\""

printf '%s\0' "${flac_files[@]}" | xargs -0 -n 1 -P "$JOBS" bash -c "$WORKER_CMD"

# ---------------- Summary ----------------
echo "==========================================================================="

# Get current counter value (files processed this run)
PROCESSED_COUNT=$(get_current_count)

if [[ -s "$LOG" ]]; then
    FAIL_COUNT=$(wc -l < "$LOG")
    FLAC_FAILS=$(grep -c "FLAC_FAIL" "$LOG" 2>/dev/null || echo 0)
    FFMPEG_FAILS=$(grep -c "FFMPEG_FAIL" "$LOG" 2>/dev/null || echo 0)

    echo -e "Status: ${COLOR_RED}FAILURES DETECTED${COLOR_RESET}"
    echo ""
    echo "Summary:"
    echo "  Total files to check  : $TOTAL_FILES"
    [[ "$RESUME" -eq 1 ]] && [[ $ALREADY_VERIFIED -gt 0 ]] && echo "  Previously verified   : $ALREADY_VERIFIED"
    echo "  Files checked this run: $PROCESSED_COUNT"
    echo "  Successfully verified : $((PROCESSED_COUNT - FAIL_COUNT))"
    echo -e "  ${COLOR_RED}Total failures        : $FAIL_COUNT${COLOR_RESET}"
    echo "    - FLAC integrity    : $FLAC_FAILS"
    [[ "$USE_FFMPEG" -eq 1 ]] && echo "    - FFmpeg decode     : $FFMPEG_FAILS"
    echo ""
    echo "Failure details saved to: $LOG"
    echo ""
    echo "To view failures:"
    log_info "cat $LOG"
    echo ""
    echo "To re-verify only failed files, you can extract them with:"
    log_info "awk -F' \\| ' '{print \$3}' $LOG | while read f; do flac -t \"\$f\"; done"
else
    echo -e "Status: ${COLOR_GREEN}ALL FILES VERIFIED SUCCESSFULLY${COLOR_RESET}"
    echo ""
    echo "Summary:"
    echo "  Total files to check  : $TOTAL_FILES"
    [[ "$RESUME" -eq 1 ]] && [[ $ALREADY_VERIFIED -gt 0 ]] && echo "  Previously verified   : $ALREADY_VERIFIED"
    echo "  Files checked this run: $PROCESSED_COUNT"
    echo "  Successfully verified : $PROCESSED_COUNT"
    echo "  Failures              : 0"
    rm -f "$LOG"
fi

# ---------------- MD5 Summary ----------------
if [[ "$CHECK_MD5" -eq 1 ]] && [[ -s "$MD5_REPORT" ]]; then
    MD5_FOLDER_COUNT=$(wc -l < "$MD5_REPORT")
    echo ""
    echo -e "${COLOR_YELLOW}⚠️  MD5 Checksum Warning${COLOR_RESET}"
    echo ""
    echo "Found $MD5_FOLDER_COUNT folder(s) with files missing MD5 checksums:"
    echo ""

    # Sort and display unique folders
    sort -u "$MD5_REPORT" | while read -r folder; do
        # Count files in this folder with missing MD5
        file_count=$(find "$folder" -maxdepth 1 -type f -iname "*.flac" -exec sh -c '
            for f; do
                if ! metaflac --show-md5sum "$f" 2>/dev/null | grep -qv "^00000000000000000000000000000000$"; then
                    echo 1
                fi
            done
        ' sh {} + | wc -l)

        echo "  📁 $folder ($file_count files)"
    done

    echo ""
    echo "To add MD5 checksums to these files, run:"
    echo "  while read folder; do"
    echo "    find \"\$folder\" -maxdepth 1 -type f -iname '*.flac' -exec metaflac --add-md5sum {} \;"
    echo "  done < $MD5_REPORT"
    echo ""
elif [[ "$CHECK_MD5" -eq 1 ]]; then
    rm -f "$MD5_REPORT"
fi

echo "==========================================================================="

# Exit with appropriate code
[[ -s "$LOG" ]] && exit 1 || exit 0