#!/bin/bash
# Scan all FLACs in current folder, summarize, and optionally re-encode.
# Parallelized version using parallel_lib.sh

set -e
set -o pipefail

# Default jobs
JOBS="${DEFAULT_JOBS:-$(nproc 2>/dev/null || echo 4)}"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j)
            JOBS="$2"
            shift 2
            ;;
        -h|--help)
            log_usage "Usage: auditas reencode [-j jobs]" "Scans and optionally re-encodes FLAC files in the current directory."
            exit 0
            ;;
        *)
            # Must source logging lib first to use it for errors
            SCRIPT_DIR_INIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            source "$SCRIPT_DIR_INIT/../lib/logging.sh"
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/parallel.sh"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

# Check for FLAC files
count=$(find . -maxdepth 1 -name "*.flac" | wc -l)
if [[ "$count" -eq 0 ]]; then
    log_info "No FLAC files found in current directory."
    exit 0
fi

# --- SCAN PHASE ---

scan_worker() {
    local f="$1"
    local vendor status
    vendor=$(metaflac --show-vendor-tag "$f" 2>/dev/null | head -n1)
    [ -z "$vendor" ] && vendor="unknown"

    if flac -t "$f" >/dev/null 2>&1; then
        status="OK"
    else
        status="FAIL"
    fi
    # Output for table: File|Vendor|Status
    printf "%s|%s|%s\n" "$f" "$vendor" "$status"
}
export -f scan_worker

log_header "Scanning $count FLAC files in current folder (Jobs: $JOBS)..."
# Run parallel scan and capture output
scan_results=$(find . -maxdepth 1 -name "*.flac" -print0 | xargs -0 -n 1 -P "$JOBS" bash -c 'scan_worker "$0"' | sort)

# Print summary
log_header "Summary of files in folder"
printf "%-30s %-25s %-6s\n" "File" "Vendor" "Status"
echo "-------------------------------------------------------------"

ok_count=0
fail_count=0
while IFS='|' read -r f vendor status; do
    printf "%-30s %-25s %-6s\n" "$f" "$vendor" "$status"
    if [[ "$status" == "OK" ]]; then
        ((ok_count++))
    else
        ((fail_count++))
    fi
done <<< "$scan_results"

log_info "Total files: $count, OK: $ok_count, FAIL: $fail_count"

# Ask if user wants to re-encode all files
log_prompt "Re-encode all files in this folder? [y/N]"
read -r answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    log_error "Aborting re-encode."
    exit 0
fi

# --- RE-ENCODE PHASE ---

reencode_worker() {
    local f="$1"
    local temp_file="tmp_$f"
    local backup_dir="backup"
    local status_msg
    
    # Ensure backup dir exists (mkdir -p is atomic/safe)
    mkdir -p "$backup_dir"

    # Encode (silence banner)
    if ! flac -"${FLAC_COMPRESSION_LEVEL:-8}" --verify --preserve-modtime "$f" -o "$temp_file" >/dev/null 2>&1; then
        status_msg="${COLOR_RED}❌ FAIL (encode)${COLOR_RESET}"
        rm -f "$temp_file"
    else
        # Verify bit-perfect audio
        old_md5=$(calculate_audio_hash "$f")
        new_md5=$(calculate_audio_hash "$temp_file")

        if [[ "$old_md5" != "$new_md5" ]]; then
            status_msg="${COLOR_RED}❌ FAIL (hash mismatch)${COLOR_RESET}"
            rm -f "$temp_file"
        else
            mv "$f" "$backup_dir/$f"
            mv "$temp_file" "$f"
            status_msg="${COLOR_GREEN}✅ Fixed${COLOR_RESET}"
        fi
    fi

    local count
    count=$(increment_counter)
    local total
    total=$(get_total_items)

    local bar
    bar=$(get_progress_bar "$count" "$total" 10)
    print_status_row "$f" "$bar" "$status_msg"
}
export -f reencode_worker increment_counter get_total_items get_progress_bar

# Initialize parallel environment
initialize_parallel "$count"

log_header "Re-encoding all files..."
printf "%-80s | %-18s | %s\n" "File" "Progress" "Status"
echo "-----------------------------------------------------------------------------"

WORKER_CMD="source \"$SCRIPT_DIR/../lib/logging.sh\"; source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/config.sh\"; source \"$SCRIPT_DIR/../lib/utils.sh\"; reencode_worker \"\$0\""
find . -maxdepth 1 -name "*.flac" -print0 | xargs -0 -n 1 -P "$JOBS" bash -c "$WORKER_CMD"

log_success "All done. Original files moved to 'backup/'."