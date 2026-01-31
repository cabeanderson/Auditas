#!/bin/bash
# Finds and removes temporary backup files and directories created by the suite.

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"

log_header "Scanning for backup files and directories..."

# Find all items to be cleaned:
# - Directories named 'backup' or 'backup_md5'
# - Files ending in .bak or .vbr.bak
# - Files starting with tmp_
mapfile -t items_to_clean < <(find . -depth -type d \( -name "backup" -o -name "backup_md5" \) -print -o -type f \( -name "*.bak" -o -name "*.vbr.bak" -o -name "tmp_*" \) -print | sort)

if [[ ${#items_to_clean[@]} -eq 0 ]]; then
    log_success "No backup files or directories found to clean."
    exit 0
fi

log_info "Found ${#items_to_clean[@]} items to clean:"
printf "  - %s\n" "${items_to_clean[@]}"
echo

log_prompt "Are you sure you want to permanently delete these items? [y/N]"
read -r answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    log_error "Aborting. No files were deleted."
    exit 0
fi

log_header "Cleaning up..."

printf '%s\0' "${items_to_clean[@]}" | xargs -0 -I {} rm -rf "{}"

log_success "Cleanup complete."