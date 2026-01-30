#!/bin/bash
# Centralized logging library for consistent output formatting and colors.

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

# --- Color Codes ---
# Use tput to be more portable and respect terminal capabilities
if tput setaf 1 >&/dev/null; then
    COLOR_RESET=$(tput sgr0)
    COLOR_RED=$(tput setaf 1)
    COLOR_GREEN=$(tput setaf 2)
    COLOR_YELLOW=$(tput setaf 3)
    COLOR_BLUE=$(tput setaf 4)
    COLOR_BOLD=$(tput bold)
else
    # Fallback to raw ANSI codes if tput is not available or fails
    COLOR_RESET="\033[0m"
    COLOR_RED="\033[31m"
    COLOR_GREEN="\033[32m"
    COLOR_YELLOW="\033[33m"
    COLOR_BLUE="\033[34m"
    COLOR_BOLD="\033[1m"
fi

# Export colors for use in subshells (e.g., xargs workers)
export COLOR_RESET COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE COLOR_BOLD

# --- Logging Functions ---

# Prints a major header.
# Usage: log_header "My Header"
log_header() {
    echo
    echo -e "${COLOR_BLUE}${COLOR_BOLD}==> ${1}${COLOR_RESET}"
}

# Prints an informational message.
# Usage: log_info "Doing something..."
log_info() {
    echo -e "    ${1}"
}

# Prints a success message.
# Usage: log_success "Operation complete."
log_success() {
    echo -e "${COLOR_GREEN}  ✓ ${1}${COLOR_RESET}"
}

# Prints an error message to stderr.
# Usage: log_error "Something went wrong."
log_error() {
    echo -e "${COLOR_RED}  ✗ ERROR: ${1}${COLOR_RESET}" >&2
}

# Prints a warning message.
# Usage: log_warning "This is deprecated."
log_warning() {
    echo -e "${COLOR_YELLOW}  ⚠️  WARNING: ${1}${COLOR_RESET}"
}

# Prints a user prompt.
# Usage: log_prompt "Continue? [y/N]"
log_prompt() {
    echo -n -e "${COLOR_YELLOW}  ? ${1}: ${COLOR_RESET}"
}

# Prints usage information in a standard format.
# Usage: log_usage "Usage: script [options]" "Description..."
log_usage() {
    echo -e "${COLOR_BOLD}${1}${COLOR_RESET}\n\n${2}"
}

# Export functions for use in subshells
export -f log_header log_info log_success log_error log_warning log_prompt log_usage