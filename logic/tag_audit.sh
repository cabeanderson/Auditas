#!/bin/bash
# Audits music library for tag quality, missing metadata, and cover art issues.
# Reports only - does not modify files.

set -e
set -o pipefail

# --- Configuration ---
ROOT="."
JOBS="${DEFAULT_JOBS:-$(nproc 2>/dev/null || echo 4)}"
OUTPUT_FILE=""
REPORT_HTML=""
CHECK_EMBEDDED_ART=1
MIN_COVER_SIZE=500  # Minimum cover art dimensions (pixels)

# Issue severity levels
declare -A SEVERITY_CRITICAL=(
    ["MISSING_ARTIST"]=1
    ["MISSING_ALBUM"]=1
    ["MISSING_TITLE"]=1
)

declare -A SEVERITY_WARNING=(
    ["MISSING_DATE"]=1
    ["MISSING_TRACKNUMBER"]=1
    ["MISSING_ALBUMARTIST"]=1
    ["MISSING_COVER"]=1
    ["LOW_RES_COVER"]=1
    ["INCONSISTENT_ALBUM"]=1
    ["INCONSISTENT_ALBUMARTIST"]=1
)

declare -A SEVERITY_INFO=(
    ["MISSING_GENRE"]=1
    ["MISSING_COMMENT"]=1
    ["NON_STANDARD_TRACKNUMBER"]=1
)

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [directory]

Audits music library for tag quality and metadata issues.

Checks performed:
  - Missing essential tags (Artist, Album, Title, Date, etc.)
  - Cover art presence (folder and embedded)
  - Cover art quality (resolution, aspect ratio)
  - Tag consistency within albums
  - Track numbering issues

OPTIONS:
  -j JOBS              Number of parallel jobs (default: nproc)
  --output FILE        Write detailed report to FILE
  --html FILE          Generate HTML report
  --no-embedded-check  Skip embedded cover art check (faster)
  -h, --help           Show this help message

SEVERITY LEVELS:
  CRITICAL: Missing Artist, Album, or Title
  WARNING:  Missing Date, Track Number, Album Artist, Cover Art
  INFO:     Missing Genre, non-standard formats

EXAMPLES:
  $(basename "$0") /music                    # Full audit
  $(basename "$0") --output issues.txt       # Save to file
  $(basename "$0") --html report.html        # HTML report
  $(basename "$0") --no-embedded-check       # Skip embedded art check (faster)

EOF
    exit 1
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -j) JOBS="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        --html) REPORT_HTML="$2"; shift 2 ;;
        --no-embedded-check) CHECK_EMBEDDED_ART=0; shift ;;
        -h|--help) usage ;;
        *) ROOT="$1"; shift ;;
    esac
done

if [[ ! -d "$ROOT" ]]; then
    echo "Error: Directory '$ROOT' not found."
    exit 1
fi

# --- Source Libraries ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/parallel.sh"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/utils.sh"

# --- Worker Function ---
audit_file_worker() {
    local f="$1"
    local issues=()
    
    # Only process FLAC files for now
    [[ "$f" != *.flac ]] && return 0
    
    # Extract tags
    local artist=$(metaflac --show-tag=ARTIST "$f" 2>/dev/null | cut -d= -f2-)
    local album=$(metaflac --show-tag=ALBUM "$f" 2>/dev/null | cut -d= -f2-)
    local title=$(metaflac --show-tag=TITLE "$f" 2>/dev/null | cut -d= -f2-)
    local date=$(metaflac --show-tag=DATE "$f" 2>/dev/null | cut -d= -f2-)
    local tracknumber=$(metaflac --show-tag=TRACKNUMBER "$f" 2>/dev/null | cut -d= -f2-)
    local albumartist=$(metaflac --show-tag=ALBUMARTIST "$f" 2>/dev/null | cut -d= -f2-)
    local genre=$(metaflac --show-tag=GENRE "$f" 2>/dev/null | cut -d= -f2-)
    
    # Critical checks
    [[ -z "$artist" ]] && issues+=("CRITICAL:MISSING_ARTIST")
    [[ -z "$album" ]] && issues+=("CRITICAL:MISSING_ALBUM")
    [[ -z "$title" ]] && issues+=("CRITICAL:MISSING_TITLE")
    
    # Warning checks
    [[ -z "$date" ]] && issues+=("WARNING:MISSING_DATE")
    [[ -z "$tracknumber" ]] && issues+=("WARNING:MISSING_TRACKNUMBER")
    [[ -z "$albumartist" ]] && issues+=("WARNING:MISSING_ALBUMARTIST")
    
    # Info checks
    [[ -z "$genre" ]] && issues+=("INFO:MISSING_GENRE")
    
    # Track number format validation
    if [[ -n "$tracknumber" ]]; then
        # Check for non-standard format (should be NN or NN/TT)
        if [[ ! "$tracknumber" =~ ^[0-9]{1,3}(/[0-9]{1,3})?$ ]]; then
            issues+=("INFO:NON_STANDARD_TRACKNUMBER:$tracknumber")
        fi
    fi
    
    # Check for embedded cover art if enabled
    if [[ $CHECK_EMBEDDED_ART -eq 1 ]]; then
        local has_embedded=$(metaflac --list --block-type=PICTURE "$f" 2>/dev/null | grep -c "PICTURE" || echo 0)
        if [[ $has_embedded -eq 0 ]]; then
            issues+=("WARNING:NO_EMBEDDED_COVER")
        fi
    fi
    
    # Output format: filepath|album|artist|issue1,issue2,issue3
    if [[ ${#issues[@]} -gt 0 ]]; then
        local issue_str=$(IFS=,; echo "${issues[*]}")
        echo "$f|$album|$artist|$issue_str"
    fi
}

# --- Album-level checks ---
check_album_issues() {
    local album_dir="$1"
    local issues=()
    
    # Find cover art files
    local has_cover=0
    for cover in "$album_dir"/{folder,cover,front}.{jpg,jpeg,png}; do
        if [[ -f "$cover" ]]; then
            has_cover=1
            
            # Check cover art quality (resolution)
            if command -v identify >/dev/null 2>&1; then
                local dimensions=$(identify -format "%wx%h" "$cover" 2>/dev/null)
                if [[ -n "$dimensions" ]]; then
                    local width=$(echo "$dimensions" | cut -dx -f1)
                    local height=$(echo "$dimensions" | cut -dx -f2)
                    
                    if [[ $width -lt $MIN_COVER_SIZE ]] || [[ $height -lt $MIN_COVER_SIZE ]]; then
                        issues+=("WARNING:LOW_RES_COVER:${width}x${height}")
                    fi
                    
                    # Check if square (allow 5% tolerance)
                    local ratio=$(awk "BEGIN {print ($width/$height)}")
                    if (( $(awk "BEGIN {print ($ratio < 0.95 || $ratio > 1.05)}") )); then
                        issues+=("INFO:NON_SQUARE_COVER:${width}x${height}")
                    fi
                fi
            fi
            break
        fi
    done
    
    [[ $has_cover -eq 0 ]] && issues+=("WARNING:MISSING_COVER")
    
    # Check tag consistency within album
    local albums=()
    local albumartists=()
    local dates=()
    
    while IFS= read -r -d '' flac; do
        local album=$(metaflac --show-tag=ALBUM "$flac" 2>/dev/null | cut -d= -f2-)
        local albumartist=$(metaflac --show-tag=ALBUMARTIST "$flac" 2>/dev/null | cut -d= -f2-)
        local date=$(metaflac --show-tag=DATE "$flac" 2>/dev/null | cut -d= -f2-)
        
        [[ -n "$album" ]] && albums+=("$album")
        [[ -n "$albumartist" ]] && albumartists+=("$albumartist")
        [[ -n "$date" ]] && dates+=("$date")
    done < <(find "$album_dir" -maxdepth 1 -type f -name "*.flac" -print0)
    
    # Check for inconsistencies
    if [[ ${#albums[@]} -gt 1 ]]; then
        local unique_albums=$(printf '%s\n' "${albums[@]}" | sort -u | wc -l)
        [[ $unique_albums -gt 1 ]] && issues+=("WARNING:INCONSISTENT_ALBUM")
    fi
    
    if [[ ${#albumartists[@]} -gt 1 ]]; then
        local unique_albumartists=$(printf '%s\n' "${albumartists[@]}" | sort -u | wc -l)
        [[ $unique_albumartists -gt 1 ]] && issues+=("WARNING:INCONSISTENT_ALBUMARTIST")
    fi
    
    if [[ ${#dates[@]} -gt 1 ]]; then
        local unique_dates=$(printf '%s\n' "${dates[@]}" | sort -u | wc -l)
        [[ $unique_dates -gt 1 ]] && issues+=("INFO:INCONSISTENT_DATE")
    fi
    
    # Output format: album_dir|issue1,issue2,issue3
    if [[ ${#issues[@]} -gt 0 ]]; then
        local issue_str=$(IFS=,; echo "${issues[*]}")
        echo "$album_dir|$issue_str"
    fi
}

# --- Main Logic ---
log_header "Music Library Tag Auditor"
log_info "Scanning: $ROOT"
[[ $CHECK_EMBEDDED_ART -eq 0 ]] && log_info "Embedded cover art check: disabled (faster)"

# Find all FLAC files
log_info "Finding FLAC files..."
mapfile -t files_to_check < <(find "$ROOT" -type f -iname '*.flac' 2>/dev/null | sort)
TOTAL_FILES=${#files_to_check[@]}

if [[ $TOTAL_FILES -eq 0 ]]; then
    log_info "No FLAC files found in '$ROOT'."
    exit 0
fi

# Find all album directories
mapfile -t album_dirs < <(find "$ROOT" -type f -iname '*.flac' -print0 | xargs -0 -n 1 dirname | sort -u)
TOTAL_ALBUMS=${#album_dirs[@]}

log_success "Found $TOTAL_FILES files in $TOTAL_ALBUMS albums"
echo ""

# Phase 1: Check individual files
log_header "Phase 1: Checking individual file tags..."
initialize_parallel "$TOTAL_FILES"

# Export functions and variables needed by workers
export -f audit_file_worker check_album_issues
export CHECK_EMBEDDED_ART MIN_COVER_SIZE

# Construct worker commands with explicit sourcing
FILE_WORKER_CMD="source \"$SCRIPT_DIR/../lib/logging.sh\"; source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/config.sh\"; source \"$SCRIPT_DIR/../lib/utils.sh\"; audit_file_worker \"\$0\""
ALBUM_WORKER_CMD="source \"$SCRIPT_DIR/../lib/logging.sh\"; source \"$SCRIPT_DIR/../lib/parallel.sh\"; source \"$SCRIPT_DIR/../lib/config.sh\"; source \"$SCRIPT_DIR/../lib/utils.sh\"; check_album_issues \"\$0\""

file_issues=$(printf '%s\0' "${files_to_check[@]}" | xargs -0 -n 1 -P "$JOBS" bash -c "$FILE_WORKER_CMD")

# Phase 2: Check album-level issues
log_header "Phase 2: Checking album-level issues..."
initialize_parallel "$TOTAL_ALBUMS"

album_issues=$(printf '%s\0' "${album_dirs[@]}" | xargs -0 -n 1 -P "$JOBS" bash -c "$ALBUM_WORKER_CMD")

# --- Process and Display Results ---
log_header "Audit Results"

# Count issues by severity
critical_count=0
warning_count=0
info_count=0
files_with_issues=0
albums_with_issues=0

# Group file issues by album
declare -A album_file_issues

while IFS='|' read -r filepath album artist issues; do
    [[ -z "$filepath" ]] && continue
    files_with_issues=$((files_with_issues + 1))
    
    local album_dir=$(dirname "$filepath")
    album_file_issues["$album_dir"]+="  $(basename "$filepath"): $issues"$'\n'
    
    # Count severity
    IFS=',' read -ra issue_array <<< "$issues"
    for issue in "${issue_array[@]}"; do
        if [[ "$issue" == CRITICAL:* ]]; then
            critical_count=$((critical_count + 1))
        elif [[ "$issue" == WARNING:* ]]; then
            warning_count=$((warning_count + 1))
        elif [[ "$issue" == INFO:* ]]; then
            info_count=$((info_count + 1))
        fi
    done
done <<< "$file_issues"

# Process album issues
declare -A album_level_issues

while IFS='|' read -r album_dir issues; do
    [[ -z "$album_dir" ]] && continue
    albums_with_issues=$((albums_with_issues + 1))
    album_level_issues["$album_dir"]="$issues"
    
    # Count severity
    IFS=',' read -ra issue_array <<< "$issues"
    for issue in "${issue_array[@]}"; do
        if [[ "$issue" == CRITICAL:* ]]; then
            critical_count=$((critical_count + 1))
        elif [[ "$issue" == WARNING:* ]]; then
            warning_count=$((warning_count + 1))
        elif [[ "$issue" == INFO:* ]]; then
            info_count=$((info_count + 1))
        fi
    done
done <<< "$album_issues"

# Summary statistics
echo "========================================================================="
echo "Summary Statistics"
echo "========================================================================="
echo ""
echo "Files scanned:           $TOTAL_FILES"
echo "Albums scanned:          $TOTAL_ALBUMS"
echo "Files with issues:       $files_with_issues"
echo "Albums with issues:      $albums_with_issues"
echo ""
echo "Issues by severity:"
[[ $critical_count -gt 0 ]] && echo -e "  ${COLOR_RED}CRITICAL: $critical_count${COLOR_RESET}" || echo "  CRITICAL: 0"
[[ $warning_count -gt 0 ]] && echo -e "  ${COLOR_YELLOW}WARNING:  $warning_count${COLOR_RESET}" || echo "  WARNING:  0"
echo "  INFO:     $info_count"
echo ""

# Display issues grouped by album
if [[ $albums_with_issues -gt 0 ]] || [[ $files_with_issues -gt 0 ]]; then
    echo "========================================================================="
    echo "Issues by Album"
    echo "========================================================================="
    echo ""
    
    # Combine all albums with issues
    declare -A all_album_issues
    for album_dir in "${!album_file_issues[@]}"; do
        all_album_issues["$album_dir"]=1
    done
    for album_dir in "${!album_level_issues[@]}"; do
        all_album_issues["$album_dir"]=1
    done
    
    # Sort and display
    for album_dir in $(printf '%s\n' "${!all_album_issues[@]}" | sort); do
        local album_name=$(basename "$album_dir")
        echo "${COLOR_BOLD}Album: $album_name${COLOR_RESET}"
        echo "Path: $album_dir"
        
        # Show album-level issues
        if [[ -n "${album_level_issues[$album_dir]}" ]]; then
            echo "Album issues: ${album_level_issues[$album_dir]}"
        fi
        
        # Show file-level issues
        if [[ -n "${album_file_issues[$album_dir]}" ]]; then
            echo "File issues:"
            echo "${album_file_issues[$album_dir]}"
        fi
        
        echo ""
    done
else
    log_success "No issues found! Library is in excellent condition."
fi

# Save to output file if requested
if [[ -n "$OUTPUT_FILE" ]]; then
    {
        echo "Music Library Audit Report"
        echo "Generated: $(date)"
        echo "Directory: $ROOT"
        echo ""
        echo "========================================================================="
        echo "Summary"
        echo "========================================================================="
        echo ""
        echo "Files scanned: $TOTAL_FILES"
        echo "Albums scanned: $TOTAL_ALBUMS"
        echo "Files with issues: $files_with_issues"
        echo "Albums with issues: $albums_with_issues"
        echo ""
        echo "CRITICAL issues: $critical_count"
        echo "WARNING issues: $warning_count"
        echo "INFO issues: $info_count"
        echo ""
        echo "========================================================================="
        echo "Detailed Issues"
        echo "========================================================================="
        echo ""
        
        # File issues
        echo "$file_issues"
        echo ""
        
        # Album issues
        echo "$album_issues"
    } > "$OUTPUT_FILE"
    
    log_success "Detailed report saved to: $OUTPUT_FILE"
fi

# Exit with error code if critical issues found
[[ $critical_count -gt 0 ]] && exit 1 || exit 0