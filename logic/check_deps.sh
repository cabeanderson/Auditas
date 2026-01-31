#!/bin/bash
# Checks for all external dependencies required by the music suite.

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/deps.sh"
source "$SCRIPT_DIR/../lib/config.sh"

if [[ -n "$LOADED_CONFIG_FILE" ]]; then
    log_info "Configuration loaded from: $LOADED_CONFIG_FILE"
else
    log_info "No configuration file found (using defaults)."
fi

all_found=1

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        log_success "$tool: found"
    else
        log_error "$tool: NOT FOUND (Required)"
        all_found=0
    fi
done

log_header "Checking for optional dependencies..."

for tool in "${OPTIONAL_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        log_success "$tool: found"
    else
        log_warning "$tool: not found (Optional, some features may be disabled or use fallbacks)"
    fi
done

echo
if [[ "$all_found" -eq 1 ]]; then
    log_success "All required dependencies are installed."
    exit 0
else
    log_error "One or more required dependencies are missing. Please install them."
    exit 1
fi