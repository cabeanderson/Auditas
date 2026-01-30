#!/bin/bash
# Library for running parallel tasks with a shared, safe progress counter.

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

SCRIPT_DIR_PARALLEL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_PARALLEL/lock.sh"

# Global-like variables for the library scope
: "${_PARALLEL_COUNTER:=}"
: "${_PARALLEL_COUNTER_LOCK:=}"
: "${_PARALLEL_TOTAL_ITEMS:=0}"

# Initializes the parallel processing environment.
# Creates temp files for counting and sets up a cleanup trap.
# Usage: initialize_parallel <total_items>
initialize_parallel() {
    export _PARALLEL_TOTAL_ITEMS=${1:-0}
    export _PARALLEL_COUNTER="/tmp/parallel_counter_$$"
    export _PARALLEL_COUNTER_LOCK="/tmp/parallel_counter_$$.lock"

    echo 0 > "$_PARALLEL_COUNTER"
    touch "$_PARALLEL_COUNTER_LOCK"
    register_temp_file "$_PARALLEL_COUNTER"
    register_temp_file "$_PARALLEL_COUNTER_LOCK"
}

# Safely increments the shared counter and returns the new count.
# The calling function should capture the output.
# Usage: new_count=$(increment_counter)
increment_counter() {
    local current next
    (
        flock -x 200
        read -r current < "$_PARALLEL_COUNTER" 2>/dev/null || current=0
        next=$((current + 1))
        printf '%s\n' "$next" > "$_PARALLEL_COUNTER"
        echo "$next"
    ) 200>"$_PARALLEL_COUNTER_LOCK"
}

# Returns the total number of items set during initialization.
get_total_items() {
    echo "$_PARALLEL_TOTAL_ITEMS"
}

# Returns the current value of the counter.
get_current_count() {
    cat "$_PARALLEL_COUNTER" 2>/dev/null || echo 0
}

# Generates a progress bar string.
# Usage: bar=$(get_progress_bar <current> <total> [width])
get_progress_bar() {
    local current=${1:-0}
    local total=${2:-1}
    local width=${3:-10}

    # Calculate percentage
    local percent=0
    if [[ $total -gt 0 ]]; then
        percent=$((current * 100 / total))
    fi

    # Calculate filled length
    local filled=0
    if [[ $total -gt 0 ]]; then
        filled=$((current * width / total))
    fi
    [[ $filled -gt $width ]] && filled=$width

    local empty=$((width - filled))

    # Build bar using string manipulation (faster and safer than seq/printf loops)
    local chars_filled="####################################################################################################"
    local chars_empty="...................................................................................................."
    local bar_str="${chars_filled:0:filled}"
    local empty_str="${chars_empty:0:empty}"

    echo "[${bar_str}${empty_str}] ${percent}%"
}
export -f get_progress_bar register_temp_file increment_counter get_total_items get_current_count