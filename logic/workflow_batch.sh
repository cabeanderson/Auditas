#!/bin/bash
# Runs a sequence of tools on directories (Batch Workflow Orchestrator).

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/config.sh"

# --- Configuration ---
DRY_RUN=0
FORCE=0
RESUME=0
SKIP_VERIFY=0
SKIP_MD5=0
SKIP_REPLAYGAIN=0
SKIP_AUDIT=0
PARALLEL_DIRS=1
AUTO_DISCOVER=0

WORKFLOW_STATE="${STATE_DIRECTORY}/batch_state"
BATCH_LOG="${LOG_DIRECTORY}/batch_workflow_$(date +%Y%m%d_%H%M%S).log"
ERRORS_SUMMARY="${LOG_DIRECTORY}/batch_errors_summary_$(date +%Y%m%d_%H%M%S).log"

# Steps in workflow
STEPS=(
    "verify:Verify FLAC Integrity"
    "md5:Check/Fix MD5 Checksums"
    "replaygain:Apply ReplayGain Tags"
    "audit:Audit Encoder Versions"
)

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [directory...]

Runs a comprehensive workflow on music directories:
  1. Verify FLAC integrity (stops if critical failures)
  2. Fix missing MD5 checksums
  3. Apply ReplayGain tags
  4. Audit encoder versions

OPTIONS:
  Workflow Control:
    --dry-run           Show what would be done without executing
    --force             Skip all confirmations
    --resume            Resume from last completed step
    
  Skip Steps:
    --skip-verify       Skip FLAC verification
    --skip-md5          Skip MD5 checksum fixes
    --skip-replaygain   Skip ReplayGain tagging
    --skip-audit        Skip encoder audit
    
  Advanced:
    --parallel-dirs N   Process N directories in parallel (default: 1)
    --auto-discover     Auto-discover album directories under given path
    
  Other:
    -h, --help          Show this help message

EXAMPLES:
  $(basename "$0") /music                    # Run full workflow
  $(basename "$0") --dry-run /music         # Preview actions
  $(basename "$0") --skip-audit /music      # Skip encoder audit
  $(basename "$0") /music/A /music/B        # Process multiple directories
  $(basename "$0") --auto-discover /music   # Auto-find albums

EOF
    exit 1
}

# --- Argument Parsing ---
DIRECTORIES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        --resume) RESUME=1; shift ;;
        --skip-verify) SKIP_VERIFY=1; shift ;;
        --skip-md5) SKIP_MD5=1; shift ;;
        --skip-replaygain) SKIP_REPLAYGAIN=1; shift ;;
        --skip-audit) SKIP_AUDIT=1; shift ;;
        --parallel-dirs) PARALLEL_DIRS="$2"; shift 2 ;;
        --auto-discover) AUTO_DISCOVER=1; shift ;;
        -h|--help) usage ;;
        -*) 
            log_error "Unknown option: $1"
            usage 
            ;;
        *) DIRECTORIES+=("$1"); shift ;;
    esac
done

# Default to current directory if none specified
[[ ${#DIRECTORIES[@]} -eq 0 ]] && DIRECTORIES=(".")

# Validate directories
for dir in "${DIRECTORIES[@]}"; do
    if [[ ! -d "$dir" ]]; then
        log_error "Directory '$dir' not found."
        exit 1
    fi
done

# --- Helper Functions ---

# Check if a step should be skipped
should_skip_step() {
    local step="$1"
    case "$step" in
        verify) [[ $SKIP_VERIFY -eq 1 ]] && return 0 ;;
        md5) [[ $SKIP_MD5 -eq 1 ]] && return 0 ;;
        replaygain) [[ $SKIP_REPLAYGAIN -eq 1 ]] && return 0 ;;
        audit) [[ $SKIP_AUDIT -eq 1 ]] && return 0 ;;
    esac
    return 1
}

# Check if step was already completed (for resume)
is_step_complete() {
    local step="$1" dir="$2"
    [[ $RESUME -eq 0 ]] && return 1
    [[ -f "$WORKFLOW_STATE" ]] || return 1
    grep -q "^${dir}:${step}:complete$" "$WORKFLOW_STATE" 2>/dev/null
}

# Mark step as complete
mark_step_complete() {
    local step="$1" dir="$2"
    echo "${dir}:${step}:complete" >> "$WORKFLOW_STATE"
}

# Pre-flight checks
preflight_checks() {
    local dir="$1"
    local issues=0
    
    # Check available disk space (need at least 1GB free for safety)
    local available=$(df -BG "$dir" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available -lt 1 ]]; then
        log_warning "Low disk space in $dir: ${available}GB available"
        issues=$((issues + 1))
    fi
    
    # Count FLAC files
    local flac_count=$(find "$dir" -type f -iname '*.flac' 2>/dev/null | wc -l)
    if [[ $flac_count -eq 0 ]]; then
        log_warning "No FLAC files found in $dir"
        return 1
    fi
    
    echo "$flac_count"
    return 0
}

# Quick scan to estimate what needs doing
estimate_work() {
    local dir="$1"
    local flac_count missing_md5 untagged_albums
    
    log_info "Analyzing $dir..."
    
    # Count FLAC files
    flac_count=$(find "$dir" -type f -iname '*.flac' 2>/dev/null | wc -l)
    
    # Estimate missing MD5 (check first track of each album)
    missing_md5=$(find "$dir" -type f \( -name '01*.flac' -o -name '01-*.flac' \) 2>/dev/null | \
        while read -r f; do
            if ! metaflac --show-md5sum "$f" 2>/dev/null | grep -qv '^00000000000000000000000000000000$'; then
                dirname "$f"
            fi
        done | sort -u | wc -l)
    
    # Estimate albums needing ReplayGain (check first track)
    untagged_albums=$(find "$dir" -type f \( -name '01*.flac' -o -name '01-*.flac' \) 2>/dev/null | \
        while read -r f; do
            if ! metaflac --list --block-type=VORBIS_COMMENT "$f" 2>/dev/null | \
                grep -q "REPLAYGAIN_REFERENCE_LOUDNESS"; then
                dirname "$f"
            fi
        done | sort -u | wc -l)
    
    echo "$flac_count|$missing_md5|$untagged_albums"
}

# Execute a workflow step
execute_step() {
    local step="$1" step_name="$2" dir="$3" step_num="$4" total_steps="$5"
    
    log_header "Step $step_num/$total_steps: $step_name"
    log_info "Directory: $dir"
    
    if should_skip_step "$step"; then
        log_warning "Skipping (--skip-${step} specified)"
        return 0
    fi
    
    if is_step_complete "$step" "$dir"; then
        log_success "Already completed (resume mode)"
        return 0
    fi
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_warning "DRY RUN: Would execute $step_name"
        return 0
    fi
    
    # Execute the actual command
    local cmd_exit=0
    case "$step" in
        verify)
            if ! "$SCRIPT_DIR/../auditas.sh" verify "$dir" >> "$BATCH_LOG" 2>&1; then
                cmd_exit=$?
                log_error "Verification failed with exit code $cmd_exit"
                echo "[$step] FAILED in $dir - see $BATCH_LOG" >> "$ERRORS_SUMMARY"
                
                # Verification failure is critical - ask user if they want to continue
                if [[ $FORCE -eq 0 ]]; then
                    log_prompt "Verification found errors. Continue anyway? [y/N]"
                    read -r answer
                    [[ ! "$answer" =~ ^[Yy]$ ]] && return 1
                fi
            fi
            ;;
        md5)
            # MD5 tool needs --fix flag, check if it needs work first
            local needs_md5=$(find "$dir" -type f \( -name '01*.flac' -o -name '01-*.flac' \) 2>/dev/null | \
                while read -r f; do
                    if ! metaflac --show-md5sum "$f" 2>/dev/null | grep -qv '^00000000000000000000000000000000$'; then
                        echo "yes"
                        break
                    fi
                done)
            
            if [[ -n "$needs_md5" ]]; then
                # Run in scan mode first to see what needs fixing
                log_info "Scanning for missing MD5 checksums..."
                "$SCRIPT_DIR/../auditas.sh" md5 "$dir" >> "$BATCH_LOG" 2>&1
                
                # In batch mode, we auto-fix without prompting if --force is set
                if [[ $FORCE -eq 1 ]]; then
                    log_info "Auto-fixing MD5 checksums (--force mode)..."
                    if ! "$SCRIPT_DIR/../auditas.sh" md5 --fix "$dir" >> "$BATCH_LOG" 2>&1; then
                        cmd_exit=$?
                        log_error "MD5 fix failed with exit code $cmd_exit"
                        echo "[$step] FAILED in $dir - see $BATCH_LOG" >> "$ERRORS_SUMMARY"
                    fi
                else
                    log_info "Missing MD5 checksums detected. Run 'auditas.sh md5 --fix $dir' to repair."
                fi
            else
                log_success "No MD5 issues found"
            fi
            ;;
        replaygain)
            if ! "$SCRIPT_DIR/../auditas.sh" replaygain "$dir" >> "$BATCH_LOG" 2>&1; then
                cmd_exit=$?
                log_error "ReplayGain failed with exit code $cmd_exit"
                echo "[$step] FAILED in $dir - see $BATCH_LOG" >> "$ERRORS_SUMMARY"
            fi
            ;;
        audit)
            if ! "$SCRIPT_DIR/../auditas.sh" audit "$dir" >> "$BATCH_LOG" 2>&1; then
                cmd_exit=$?
                log_error "Audit failed with exit code $cmd_exit"
                echo "[$step] FAILED in $dir - see $BATCH_LOG" >> "$ERRORS_SUMMARY"
            fi
            ;;
    esac
    
    if [[ $cmd_exit -eq 0 ]]; then
        log_success "Step completed successfully"
        mark_step_complete "$step" "$dir"
        return 0
    else
        return $cmd_exit
    fi
}

# Process a single directory through the workflow
process_directory() {
    local dir="$1"
    
    log_header "Processing Directory: $dir"
    
    # Pre-flight checks
    local file_count
    if ! file_count=$(preflight_checks "$dir"); then
        log_warning "Skipping $dir (no FLAC files found)"
        return 0
    fi
    
    log_info "Found $file_count FLAC files"
    
    # Count active steps
    local active_steps=0
    for step_def in "${STEPS[@]}"; do
        local step="${step_def%%:*}"
        should_skip_step "$step" || active_steps=$((active_steps + 1))
    done
    
    # Execute each step
    local step_num=1
    local failed=0
    for step_def in "${STEPS[@]}"; do
        local step="${step_def%%:*}"
        local step_name="${step_def#*:}"
        
        should_skip_step "$step" && continue
        
        if ! execute_step "$step" "$step_name" "$dir" "$step_num" "$active_steps"; then
            failed=1
            # Don't break - continue with other steps and report all errors
        fi
        
        step_num=$((step_num + 1))
        echo "" # Blank line between steps
    done
    
    if [[ $failed -eq 0 ]]; then
        log_success "Directory completed successfully: $dir"
    else
        log_error "Directory completed with errors: $dir"
    fi
    
    return $failed
}

# --- Main Logic ---

log_header "Batch Workflow Orchestrator"
[[ $DRY_RUN -eq 1 ]] && log_warning "DRY RUN MODE - No changes will be made"
[[ $RESUME -eq 1 ]] && log_info "Resume mode enabled"

# Auto-discover album directories if requested
if [[ $AUTO_DISCOVER -eq 1 ]]; then
    log_info "Auto-discovering album directories..."
    mapfile -t discovered < <(find "${DIRECTORIES[@]}" -type f -iname '*.flac' -print0 | \
        xargs -0 -n 1 dirname | sort -u)
    
    if [[ ${#discovered[@]} -gt 0 ]]; then
        log_success "Discovered ${#discovered[@]} album directories"
        DIRECTORIES=("${discovered[@]}")
    else
        log_error "No album directories found"
        exit 1
    fi
fi

# Show workflow plan
log_header "Workflow Plan"
echo ""
echo "Directories to process: ${#DIRECTORIES[@]}"
for dir in "${DIRECTORIES[@]}"; do
    echo "  - $dir"
done
echo ""

echo "Steps to execute:"
local step_num=1
for step_def in "${STEPS[@]}"; do
    local step="${step_def%%:*}"
    local step_name="${step_def#*:}"
    
    if should_skip_step "$step"; then
        echo "  $step_num. [SKIPPED] $step_name"
    else
        echo "  $step_num. [ACTIVE] $step_name"
    fi
    step_num=$((step_num + 1))
done
echo ""

# Quick analysis for user
if [[ $DRY_RUN -eq 0 ]] && [[ ${#DIRECTORIES[@]} -le 5 ]]; then
    log_info "Quick analysis..."
    for dir in "${DIRECTORIES[@]}"; do
        IFS='|' read -r flac_count missing_md5 untagged_albums < <(estimate_work "$dir")
        echo "  $dir:"
        echo "    - FLAC files: $flac_count"
        [[ $SKIP_MD5 -eq 0 ]] && echo "    - Albums with missing MD5: ~$missing_md5"
        [[ $SKIP_REPLAYGAIN -eq 0 ]] && echo "    - Albums needing ReplayGain: ~$untagged_albums"
    done
    echo ""
fi

log_info "Logs will be saved to: $BATCH_LOG"
[[ -f "$ERRORS_SUMMARY" ]] || touch "$ERRORS_SUMMARY"

# Confirmation (unless --force)
if [[ $FORCE -eq 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
    log_prompt "Continue with batch workflow? [y/N]"
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_error "Aborted by user"
        exit 0
    fi
fi

echo ""

# Process directories
total_dirs=${#DIRECTORIES[@]}
completed=0
failed=0

for dir in "${DIRECTORIES[@]}"; do
    if process_directory "$dir"; then
        completed=$((completed + 1))
    else
        failed=$((failed + 1))
    fi
    echo ""
    echo "========================================================================="
    echo ""
done

# --- Final Summary ---
log_header "Batch Workflow Complete"
echo ""
echo "Summary:"
echo "  Total directories: $total_dirs"
echo "  Completed successfully: $completed"
if [[ $failed -gt 0 ]]; then
    echo -e "  ${COLOR_RED}Completed with errors: $failed${COLOR_RESET}"
else
    echo -e "  ${COLOR_GREEN}Completed with errors: 0${COLOR_RESET}"
fi
echo ""

if [[ -s "$ERRORS_SUMMARY" ]]; then
    log_error "Errors encountered during workflow:"
    cat "$ERRORS_SUMMARY" | sed 's/^/  /'
    echo ""
    echo "Full logs: $BATCH_LOG"
    echo "Error summary: $ERRORS_SUMMARY"
    exit 1
else
    log_success "All directories processed without errors!"
    rm -f "$ERRORS_SUMMARY"
    
    if [[ $DRY_RUN -eq 0 ]]; then
        echo ""
        echo "Full logs: $BATCH_LOG"
    fi
    
    # Clean up state file if everything succeeded
    [[ -f "$WORKFLOW_STATE" ]] && rm -f "$WORKFLOW_STATE"
    
#!/bin/bash
# Runs a sequence of tools on directories (Batch Workflow Orchestrator).

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/config.sh"

# --- Configuration ---
DRY_RUN=0
FORCE=0
RESUME=0
SKIP_VERIFY=0
SKIP_MD5=0
SKIP_REPLAYGAIN=0
SKIP_AUDIT=0
PARALLEL_DIRS=1
AUTO_DISCOVER=0

WORKFLOW_STATE="${STATE_DIRECTORY}/batch_state"
BATCH_LOG="${LOG_DIRECTORY}/batch_workflow_$(date +%Y%m%d_%H%M%S).log"
ERRORS_SUMMARY="${LOG_DIRECTORY}/batch_errors_summary_$(date +%Y%m%d_%H%M%S).log"

# Determine main script location (handle rename)
AUDITAS_CMD="$SCRIPT_DIR/../auditas"
if [[ ! -f "$AUDITAS_CMD" ]]; then
    AUDITAS_CMD="$SCRIPT_DIR/../auditas.sh"
fi

# Steps in workflow
STEPS=(
    "verify:Verify FLAC Integrity"
    "md5:Check/Fix MD5 Checksums"
    "replaygain:Apply ReplayGain Tags"
    "audit:Audit Encoder Versions"
)

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [directory...]

Runs a comprehensive workflow on music directories:
  1. Verify FLAC integrity (stops if critical failures)
  2. Fix missing MD5 checksums
  3. Apply ReplayGain tags
  4. Audit encoder versions

OPTIONS:
  Workflow Control:
    --dry-run           Show what would be done without executing
    --force             Skip all confirmations
    --resume            Resume from last completed step
    
  Skip Steps:
    --skip-verify       Skip FLAC verification
    --skip-md5          Skip MD5 checksum fixes
    --skip-replaygain   Skip ReplayGain tagging
    --skip-audit        Skip encoder audit
    
  Advanced:
    --parallel-dirs N   Process N directories in parallel (default: 1)
    --auto-discover     Auto-discover album directories under given path
    
  Other:
    -h, --help          Show this help message

EXAMPLES:
  $(basename "$0") /music                    # Run full workflow
  $(basename "$0") --dry-run /music         # Preview actions
  $(basename "$0") --skip-audit /music      # Skip encoder audit
  $(basename "$0") /music/A /music/B        # Process multiple directories
  $(basename "$0") --auto-discover /music   # Auto-find albums

EOF
    exit 1
}

# --- Argument Parsing ---
DIRECTORIES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        --resume) RESUME=1; shift ;;
        --skip-verify) SKIP_VERIFY=1; shift ;;
        --skip-md5) SKIP_MD5=1; shift ;;
        --skip-replaygain) SKIP_REPLAYGAIN=1; shift ;;
        --skip-audit) SKIP_AUDIT=1; shift ;;
        --parallel-dirs) PARALLEL_DIRS="$2"; shift 2 ;;
        --auto-discover) AUTO_DISCOVER=1; shift ;;
        -h|--help) usage ;;
        -*) 
            log_error "Unknown option: $1"
            usage 
            ;;
        *) DIRECTORIES+=("$1"); shift ;;
    esac
}

# Default to current directory if none specified
[[ ${#DIRECTORIES[@]} -eq 0 ]] && DIRECTORIES=(".")

# Validate directories
for dir in "${DIRECTORIES[@]}"; do
    if [[ ! -d "$dir" ]]; then
        log_error "Directory '$dir' not found."
        exit 1
    fi
done

# --- Helper Functions ---

# Check if a step should be skipped
should_skip_step() {
    local step="$1"
    case "$step" in
        verify) [[ $SKIP_VERIFY -eq 1 ]] && return 0 ;;
        md5) [[ $SKIP_MD5 -eq 1 ]] && return 0 ;;
        replaygain) [[ $SKIP_REPLAYGAIN -eq 1 ]] && return 0 ;;
        audit) [[ $SKIP_AUDIT -eq 1 ]] && return 0 ;;
    esac
    return 1
}

# Check if step was already completed (for resume)
is_step_complete() {
    local step="$1" dir="$2"
    [[ $RESUME -eq 0 ]] && return 1
    [[ -f "$WORKFLOW_STATE" ]] || return 1
    grep -q "^${dir}:${step}:complete$" "$WORKFLOW_STATE" 2>/dev/null
}

# Mark step as complete
mark_step_complete() {
    local step="$1" dir="$2"
    echo "${dir}:${step}:complete" >> "$WORKFLOW_STATE"
}

# Pre-flight checks
preflight_checks() {
    local dir="$1"
    local issues=0
    
    # Check available disk space (need at least 1GB free for safety)
    local available=$(df -BG "$dir" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available -lt 1 ]]; then
        log_warning "Low disk space in $dir: ${available}GB available"
        issues=$((issues + 1))
    fi
    
    # Count FLAC files
    local flac_count=$(find "$dir" -type f -iname '*.flac' 2>/dev/null | wc -l)
    if [[ $flac_count -eq 0 ]]; then
        log_warning "No FLAC files found in $dir"
        return 1
    fi
    
    echo "$flac_count"
    return 0
}

# Quick scan to estimate what needs doing
estimate_work() {
    local dir="$1"
    local flac_count missing_md5 untagged_albums
    
    log_info "Analyzing $dir..."
    
    # Count FLAC files
    flac_count=$(find "$dir" -type f -iname '*.flac' 2>/dev/null | wc -l)
    
    # Estimate missing MD5 (check first track of each album)
    missing_md5=$(find "$dir" -type f \( -name '01*.flac' -o -name '01-*.flac' \) 2>/dev/null | \
        while read -r f; do
            if ! metaflac --show-md5sum "$f" 2>/dev/null | grep -qv '^00000000000000000000000000000000$'; then
                dirname "$f"
            fi
        done | sort -u | wc -l)
    
    # Estimate albums needing ReplayGain (check first track)
    untagged_albums=$(find "$dir" -type f \( -name '01*.flac' -o -name '01-*.flac' \) 2>/dev/null | \
        while read -r f; do
            if ! metaflac --list --block-type=VORBIS_COMMENT "$f" 2>/dev/null | \
                grep -q "REPLAYGAIN_REFERENCE_LOUDNESS"; then
                dirname "$f"
            fi
        done | sort -u | wc -l)
    
    echo "$flac_count|$missing_md5|$untagged_albums"
}

# Execute a workflow step
execute_step() {
    local step="$1" step_name="$2" dir="$3" step_num="$4" total_steps="$5"
    
    log_header "Step $step_num/$total_steps: $step_name"
    log_info "Directory: $dir"
    
    if should_skip_step "$step"; then
        log_warning "Skipping (--skip-${step} specified)"
        return 0
    fi
    
    if is_step_complete "$step" "$dir"; then
        log_success "Already completed (resume mode)"
        return 0
    fi
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_warning "DRY RUN: Would execute $step_name"
        return 0
    fi
    
    # Execute the actual command
    local cmd_exit=0
    case "$step" in
        verify)
            if ! "$AUDITAS_CMD" verify "$dir" >> "$BATCH_LOG" 2>&1; then
                cmd_exit=$?
                log_error "Verification failed with exit code $cmd_exit"
                echo "[$step] FAILED in $dir - see $BATCH_LOG" >> "$ERRORS_SUMMARY"
                
                # Verification failure is critical - ask user if they want to continue
                if [[ $FORCE -eq 0 ]]; then
                    log_prompt "Verification found errors. Continue anyway? [y/N]"
                    read -r answer
                    [[ ! "$answer" =~ ^[Yy]$ ]] && return 1
                fi
            fi
            ;;
        md5)
            # MD5 tool needs --fix flag, check if it needs work first
            local needs_md5=$(find "$dir" -type f \( -name '01*.flac' -o -name '01-*.flac' \) 2>/dev/null | \
                while read -r f; do
                    if ! metaflac --show-md5sum "$f" 2>/dev/null | grep -qv '^00000000000000000000000000000000$'; then
                        echo "yes"
                        break
                    fi
                done)
            
            if [[ -n "$needs_md5" ]]; then
                # Run in scan mode first to see what needs fixing
                log_info "Scanning for missing MD5 checksums..."
                "$AUDITAS_CMD" md5 "$dir" >> "$BATCH_LOG" 2>&1
                
                # In batch mode, we auto-fix without prompting if --force is set
                if [[ $FORCE -eq 1 ]]; then
                    log_info "Auto-fixing MD5 checksums (--force mode)..."
                    if ! "$AUDITAS_CMD" md5 --fix "$dir" >> "$BATCH_LOG" 2>&1; then
                        cmd_exit=$?
                        log_error "MD5 fix failed with exit code $cmd_exit"
                        echo "[$step] FAILED in $dir - see $BATCH_LOG" >> "$ERRORS_SUMMARY"
                    fi
                else
                    log_info "Missing MD5 checksums detected. Run '$(basename "$AUDITAS_CMD") md5 --fix $dir' to repair."
                fi
            else
                log_success "No MD5 issues found"
            fi
            ;;
        replaygain)
            if ! "$AUDITAS_CMD" replaygain "$dir" >> "$BATCH_LOG" 2>&1; then
                cmd_exit=$?
                log_error "ReplayGain failed with exit code $cmd_exit"
                echo "[$step] FAILED in $dir - see $BATCH_LOG" >> "$ERRORS_SUMMARY"
            fi
            ;;
        audit)
            if ! "$AUDITAS_CMD" audit "$dir" >> "$BATCH_LOG" 2>&1; then
                cmd_exit=$?
                log_error "Audit failed with exit code $cmd_exit"
                echo "[$step] FAILED in $dir - see $BATCH_LOG" >> "$ERRORS_SUMMARY"
            fi
            ;;
    esac
    
    if [[ $cmd_exit -eq 0 ]]; then
        log_success "Step completed successfully"
        mark_step_complete "$step" "$dir"
        return 0
    else
        return $cmd_exit
    fi
}

# Process a single directory through the workflow
process_directory() {
    local dir="$1"
    
    log_header "Processing Directory: $dir"
    
    # Pre-flight checks
    local file_count
    if ! file_count=$(preflight_checks "$dir"); then
        log_warning "Skipping $dir (no FLAC files found)"
        return 0
    fi
    
    log_info "Found $file_count FLAC files"
    
    # Count active steps
    local active_steps=0
    for step_def in "${STEPS[@]}"; do
        local step="${step_def%%:*}"
        should_skip_step "$step" || active_steps=$((active_steps + 1))
    done
    
    # Execute each step
    local step_num=1
    local failed=0
    for step_def in "${STEPS[@]}"; do
        local step="${step_def%%:*}"
        local step_name="${step_def#*:}"
        
        should_skip_step "$step" && continue
        
        if ! execute_step "$step" "$step_name" "$dir" "$step_num" "$active_steps"; then
            failed=1
            # Don't break - continue with other steps and report all errors
        fi
        
        step_num=$((step_num + 1))
        echo "" # Blank line between steps
    done
    
    if [[ $failed -eq 0 ]]; then
        log_success "Directory completed successfully: $dir"
    else
        log_error "Directory completed with errors: $dir"
    fi
    
    return $failed
}

# --- Main Logic ---

log_header "Batch Workflow Orchestrator"
[[ $DRY_RUN -eq 1 ]] && log_warning "DRY RUN MODE - No changes will be made"
[[ $RESUME -eq 1 ]] && log_info "Resume mode enabled"

# Auto-discover album directories if requested
if [[ $AUTO_DISCOVER -eq 1 ]]; then
    log_info "Auto-discovering album directories..."
    mapfile -t discovered < <(find "${DIRECTORIES[@]}" -type f -iname '*.flac' -print0 | \
        xargs -0 -n 1 dirname | sort -u)
    
    if [[ ${#discovered[@]} -gt 0 ]]; then
        log_success "Discovered ${#discovered[@]} album directories"
        DIRECTORIES=("${discovered[@]}")
    else
        log_error "No album directories found"
        exit 1
    fi
fi

# Show workflow plan
log_header "Workflow Plan"
echo ""
echo "Directories to process: ${#DIRECTORIES[@]}"
for dir in "${DIRECTORIES[@]}"; do
    echo "  - $dir"
done
echo ""

echo "Steps to execute:"
local step_num=1
for step_def in "${STEPS[@]}"; do
    local step="${step_def%%:*}"
    local step_name="${step_def#*:}"
    
    if should_skip_step "$step"; then
        echo "  $step_num. [SKIPPED] $step_name"
    else
        echo "  $step_num. [ACTIVE] $step_name"
    fi
    step_num=$((step_num + 1))
done
echo ""

# Quick analysis for user
if [[ $DRY_RUN -eq 0 ]] && [[ ${#DIRECTORIES[@]} -le 5 ]]; then
    log_info "Quick analysis..."
    for dir in "${DIRECTORIES[@]}"; do
        IFS='|' read -r flac_count missing_md5 untagged_albums < <(estimate_work "$dir")
        echo "  $dir:"
        echo "    - FLAC files: $flac_count"
        [[ $SKIP_MD5 -eq 0 ]] && echo "    - Albums with missing MD5: ~$missing_md5"
        [[ $SKIP_REPLAYGAIN -eq 0 ]] && echo "    - Albums needing ReplayGain: ~$untagged_albums"
    done
    echo ""
fi

log_info "Logs will be saved to: $BATCH_LOG"
[[ -f "$ERRORS_SUMMARY" ]] || touch "$ERRORS_SUMMARY"

# Confirmation (unless --force)
if [[ $FORCE -eq 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
    log_prompt "Continue with batch workflow? [y/N]"
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_error "Aborted by user"
        exit 0
    fi
fi

echo ""

# Process directories
total_dirs=${#DIRECTORIES[@]}
completed=0
failed=0

for dir in "${DIRECTORIES[@]}"; do
    if process_directory "$dir"; then
        completed=$((completed + 1))
    else
        failed=$((failed + 1))
    fi
    echo ""
    echo "========================================================================="
    echo ""
done

# --- Final Summary ---
log_header "Batch Workflow Complete"
echo ""
echo "Summary:"
echo "  Total directories: $total_dirs"
echo "  Completed successfully: $completed"
if [[ $failed -gt 0 ]]; then
    echo -e "  ${COLOR_RED}Completed with errors: $failed${COLOR_RESET}"
else
    echo -e "  ${COLOR_GREEN}Completed with errors: 0${COLOR_RESET}"
fi
echo ""

if [[ -s "$ERRORS_SUMMARY" ]]; then
    log_error "Errors encountered during workflow:"
    cat "$ERRORS_SUMMARY" | sed 's/^/  /'
    echo ""
    echo "Full logs: $BATCH_LOG"
    echo "Error summary: $ERRORS_SUMMARY"
    exit 1
else
    log_success "All directories processed without errors!"
    rm -f "$ERRORS_SUMMARY"
    
    if [[ $DRY_RUN -eq 0 ]]; then
        echo ""
        echo "Full logs: $BATCH_LOG"
    fi
    
    # Clean up state file if everything succeeded
    [[ -f "$WORKFLOW_STATE" ]] && rm -f "$WORKFLOW_STATE"
    
    exit 0
fi