#!/bin/bash
# Library for managing lock files and temporary file cleanup.

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

_LOCK_TEMP_FILES=()

# Registers a file to be cleaned up automatically on exit.
# Usage: register_temp_file "/tmp/my_lock_file"
register_temp_file() {
    _LOCK_TEMP_FILES+=("$1")
    touch "$1" # Ensure it exists so rm doesn't complain
}

# Internal cleanup function called by trap
_lock_cleanup() {
    rm -f "${_LOCK_TEMP_FILES[@]}"
}

# Initialize the trap
# Note: If other libraries also set traps, this might need coordination.
# For this suite, we assume this is the primary cleanup mechanism.
trap _lock_cleanup EXIT INT TERM

export -f register_temp_file