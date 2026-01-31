#!/bin/bash
# MP3 integrity checker and repair tool.
# Combines functionality of mp3val (general) and vbrfixc (VBR headers).

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

set -e
set -o pipefail

MODE="scan"
DIR="."
JOBS="${DEFAULT_JOBS:-$(nproc 2>/dev/null || echo 4)}"

usage() {
    log_usage "Usage: auditas mp3 [--fix] [directory]" "

Scans MP3 files for integrity issues and missing VBR headers.

OPTIONS:
  -j JOBS Number of parallel jobs (default: nproc)
  --fix   Attempt to repair detected issues.
          - Uses 'mp3val' for stream errors.
          - Uses 'vbrfixc' for missing VBR headers.
          - Creates backups (.bak) before modifying files.
  -h      Show this help message."
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -j) JOBS="$2"; shift 2 ;;
        --fix) MODE="fix"; shift ;;
        -h|--help) usage ;;
        *) DIR="$1"; shift ;;
    esac
done

if [[ ! -d "$DIR" ]]; then
    echo "Error: Directory '$DIR' not found."
    exit 1
fi

# Source the parallel library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/parallel.sh"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/lock.sh"

mapfile -t mp3_files < <(find "$DIR" -type f -iname '*.mp3' | sort)
TOTAL_FILES=${#mp3_files[@]}

if [[ $TOTAL_FILES -eq 0 ]]; then
    log_info "No MP3 files found in '$DIR'."
    exit 0
fi

log_header "Scanning $TOTAL_FILES MP3s in '$DIR' using $JOBS jobs..."
if [[ "$MODE" == "fix" ]]; then
    log_warning "FIX MODE ENABLED: Files will be modified. Backups created."
else
    log_info "SCAN MODE: Reporting only. Use --fix to repair."
fi

# --- Worker Function ---
mp3_worker() {
    local f="$1"
    # Run mp3val in scan mode, capture output
    # -si suppresses info messages, leaving mostly warnings/errors
    local val_out=$(mp3val -si "$f" 2>&1)
    
    # Check if mp3val found anything significant
    # mp3val usually outputs "No problems found" if clean, or specific warnings
    if [[ "$val_out" != *"No problems found"* ]] && [[ -n "$val_out" ]]; then
        
        # Identify specific VBR issue
        is_vbr_issue=0
        if [[ "$val_out" == *"VBR detected, but no VBR header"* ]]; then
            is_vbr_issue=1
        fi

        # Use a lock to prevent interleaved output from different processes
        (
            flock -x 200
            log_header "Issues detected in: $f"
            echo "$val_out" | sed 's/^/  /' # Indent output

            if [[ "$MODE" == "fix" ]]; then
                # 1. Fix general stream errors with mp3val
                # mp3val creates its own .bak file.
                log_info "Running mp3val repair..."
                if mp3val -f -si "$f" >/dev/null 2>&1; then
                     log_success "mp3val repair complete."
                else
                     log_error "mp3val repair failed."
                fi

                # 2. Fix VBR if needed (requires vbrfixc)
                if [[ $is_vbr_issue -eq 1 ]] && command -v vbrfixc >/dev/null 2>&1; then
                    log_info "Running vbrfixc..."
                    tmpfile="${f%.mp3}_fixed.mp3"
                    if vbrfixc "$f" "$tmpfile" >/dev/null 2>&1; then
                        mv "$f" "$f.vbr.bak"
                        mv "$tmpfile" "$f"
                        log_success "VBR header reconstructed (original backed up as .vbr.bak)"
                    else
                        log_error "vbrfixc failed."
                        rm -f "$tmpfile"
                    fi
                elif [[ $is_vbr_issue -eq 1 ]]; then
                    log_warning "vbrfixc not found, skipping VBR fix."
                fi
            fi
        ) 200>"/tmp/mp3_tool_$$.lock"
    fi
}
export -f mp3_worker
export MODE

# --- Main Execution ---

# Create lock file for printing and set trap to clean it up
# We need to initialize parallel lib even if we don't use the counter heavily yet,
# just to get the trap/cleanup logic.
initialize_parallel "$TOTAL_FILES"

PRINT_LOCK="/tmp/mp3_tool_$$.lock"
register_temp_file "$PRINT_LOCK"

WORKER_CMD="source \"$SCRIPT_DIR/../lib/logging.sh\"; source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/config.sh\"; source \"$SCRIPT_DIR/../lib/lock.sh\"; source \"$SCRIPT_DIR/../lib/utils.sh\"; mp3_worker \"\$0\""
printf '%s\0' "${mp3_files[@]}" | xargs -0 -n 1 -P "$JOBS" bash -c "$WORKER_CMD"

log_header "Scan complete."