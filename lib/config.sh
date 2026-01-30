#!/bin/bash
# Library to load configuration for the music suite.

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

# Default values
: "${MUSIC_SUITE_VERSION:=1.0.0}"
: "${DEFAULT_JOBS:=$(nproc 2>/dev/null || echo 4)}"
: "${FLAC_COMPRESSION_LEVEL:=8}"
: "${REPLAYGAIN_TARGET:=-18}"
: "${MIN_COVER_SIZE:=500}"

# XDG Base Directory Standards
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"

# Define paths based on XDG standards
: "${LOG_DIRECTORY:=$XDG_DATA_HOME/music_suite/logs}"
: "${STATE_DIRECTORY:=$XDG_STATE_HOME/music_suite/state}"
: "${CACHE_DIRECTORY:=$STATE_DIRECTORY}" # Map cache to state directory as requested

LOADED_CONFIG_FILE=""

# Function to load config file
load_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        # Source the config file. 
        # We use 'set -a' to automatically export variables defined in the config.
        set -a
        source "$config_file"
        set +a
        LOADED_CONFIG_FILE="$config_file"
    fi
}

# Load Configuration Hierarchy
load_config "/etc/music_suite/config"
load_config "$XDG_CONFIG_HOME/music_suite/config"
load_config "./music_suite.conf"


# Ensure directories exist
mkdir -p "$LOG_DIRECTORY" "$CACHE_DIRECTORY" "$STATE_DIRECTORY"

export MUSIC_SUITE_VERSION DEFAULT_JOBS FLAC_COMPRESSION_LEVEL REPLAYGAIN_TARGET MIN_COVER_SIZE LOADED_CONFIG_FILE
export LOG_DIRECTORY CACHE_DIRECTORY STATE_DIRECTORY