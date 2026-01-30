#!/bin/bash
# Shared utility functions for the music suite.

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

# Calculates the MD5 hash of the raw audio stream using ffmpeg.
# Usage: hash=$(calculate_audio_hash "file.flac")
calculate_audio_hash() {
    local f="$1"
    # -v error: silence info output
    # -f wav: decode to raw wav
    # -: output to stdout
    ffmpeg -v error -i "$f" -f wav - | md5sum | awk '{print $1}'
}

# Truncates a path string to a maximum length, keeping the start and end.
# Usage: truncated=$(truncate_path "/very/long/path/to/file.flac" 35)
truncate_path() {
    local p="$1" max="$2"
    if [[ ${#p} -le $max ]]; then
        printf "%s" "$p"
    else
        local keep=$((max - 3))
        local start=$((keep / 2))
        local end=$((keep - start))
        printf "%s...%s" "${p:0:$start}" "${p: -$end}"
    fi
}

# Prints a standardized status row with alignment
# Usage: print_status_row "Name" "Progress Bar" "Status Message" [width]
print_status_row() {
    local name="$1"
    local bar="$2"
    local status="$3"
    local width="${4:-80}"

    local display_name=$(truncate_path "$name" "$width")
    display_name=${display_name%$'\r'}
    
    printf "%-${width}s | %-18s | %b\n" "$display_name" "$bar" "$status"
}

export -f calculate_audio_hash truncate_path print_status_row