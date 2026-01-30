#!/bin/bash
# Recursively scans the first track of each album to audit FLAC integrity and encoder version.
# This version is parallelized for speed.

set -e
set -o pipefail

# --- Defaults ---
STRICT_MODE=0
OUTPUT_FILE=""
ROOT="."
JOBS="${DEFAULT_JOBS:-$(nproc 2>/dev/null || echo 4)}"

# --- Usage ---
usage() {
    log_usage "Usage: $(basename "$0") [OPTIONS] [directory]" "

Audits the first track of each FLAC album for encoder version and integrity.

OPTIONS:
  -j JOBS         Number of parallel jobs (default: nproc)
  --strict        Use stricter rules for encoder versions:
                  - Green: 1.3.0+
                  - Yellow: 1.2.*
                  - Red: <1.2.0, non-reference encoders, or unknown
                  (Default is Green for 1.3.0+, Yellow for others)
  --output FILE   Write a list of files needing attention (red status) to FILE.
  -h, --help      Show this help message."
    exit 1
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j)
            JOBS="$2"
            shift 2
            ;;
        --strict)
            STRICT_MODE=1
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            ROOT="$1"
            shift
            ;;
    esac
done

# Source the parallel library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/parallel.sh"
source "$SCRIPT_DIR/../lib/config.sh"

# --- Worker Function ---
audit_worker() {
    local f="$1"
    local dir file version color_code status ver_num encoder_name major minor

    dir=$(dirname "$f")
    file=$(basename "$f")

    version=$(metaflac --show-vendor-tag "$f" 2>/dev/null)
    color_code="yellow" # Default

    if [[ -z "$version" ]]; then
        version="unknown"
        color_code="red"
    else
        ver_num=$(echo "$version" | grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' | head -n1)
        encoder_name=$(echo "$version" | awk '{print $1}')

        if [[ "$STRICT_MODE" -eq 1 ]]; then
            if [[ "$encoder_name" != "reference" ]]; then
                color_code="red"
            elif [[ -n "$ver_num" ]]; then
                major=$(echo "$ver_num" | cut -d. -f1); minor=$(echo "$ver_num" | cut -d. -f2)
                if (( major == 1 && minor >= 3 )); then color_code="green"; elif (( major == 1 && minor == 2 )); then color_code="yellow"; else color_code="red"; fi
            else
                color_code="red"
            fi
        else
            if [[ -n "$ver_num" ]]; then
                major=$(echo "$ver_num" | cut -d. -f1); minor=$(echo "$ver_num" | cut -d. -f2)
                if (( major == 1 && minor >= 3 )); then color_code="green"; else color_code="yellow"; fi
            fi
        fi
    fi

    if flac -t "$f" >/dev/null 2>&1; then status="✅ OK"; else status="❌ FAIL"; color_code="red"; fi

    # Output format: color_code|dir|file|version|status
    printf "%s|%s|%s|%s|%s\n" "$color_code" "$dir" "$file" "$version" "$status"
}
export -f audit_worker
export STRICT_MODE

# --- Main Logic ---
log_header "Scanning for first tracks..."
mapfile -t files_to_audit < <(find "$ROOT" -type f \( -name '01*.flac' -o -name '01-*.flac' \) | sort)

if [[ ${#files_to_audit[@]} -eq 0 ]]; then
    log_info "No first tracks found to audit."
    exit 0
fi

log_header "Auditing ${#files_to_audit[@]} albums using $JOBS jobs..."

# Run in parallel, capture results
WORKER_CMD="source \"$SCRIPT_DIR/../lib/logging.sh\"; source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/config.sh\"; audit_worker \"\$0\""
audit_results=$(printf '%s\0' "${files_to_audit[@]}" | xargs -0 -n 1 -P "$JOBS" bash -c "$WORKER_CMD")

# --- Output Processing ---
echo "Folder | File | FLAC Version | Status"
echo "----------------------------------------"

# Clear output file if specified
if [[ -n "$OUTPUT_FILE" ]]; then
    > "$OUTPUT_FILE"
    log_info "Writing items needing attention to: $OUTPUT_FILE"
fi

# Process results serially for clean output
while IFS='|' read -r color_code dir file version status; do
    color=""
    case "$color_code" in
        red)    color="${COLOR_RED}" ;;
        green)  color="${COLOR_GREEN}" ;;
        yellow) color="${COLOR_YELLOW}" ;;
    esac

    printf "%s | %s | ${color}%s\033[0m | %s\n" "$dir" "$file" "$version" "$status"

    if [[ -n "$OUTPUT_FILE" && "$color_code" == "red" ]]; then
        # Reconstruct full path for the log file
        echo "$dir/$file | $version | $status" >> "$OUTPUT_FILE"
    fi
done <<< "$audit_results"