#!/bin/bash
# Master dispatcher for the music library management suite.
# Usage: ./music_suite.sh [COMMAND] [ARGS]

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

set -e
set -o pipefail

# Resolve the directory where this script is located (handling symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/config.sh"

usage() {
    log_usage "Usage: $(basename "$0") [COMMAND] [OPTIONS]" "

A suite of tools for managing and verifying digital music libraries.

COMMANDS:
  verify         Verify integrity of all FLAC files (parallel)
  md5            Scan or fix missing FLAC MD5 checksums
  reencode       Re-encode FLACs in the current folder (with verification)
  audit          Audit FLAC encoder versions and integrity of first tracks
  tag-audit      Audit files for missing tags and cover art
  mp3            Scan or fix MP3 library (integrity & VBR headers)
  verify-gen     Verify OGG, Opus, M4A, WAV, etc. using ffmpeg
  replaygain     Apply ReplayGain tags to FLAC albums
  batch          Run standard workflow (Verify -> MD5 -> ReplayGain -> Audit)
  clean          Remove temporary backup files and directories
  check-deps     Check for all required external tools

  -v, --version  Show version information
Run '$(basename "$0") [COMMAND] --help' for details on a specific command."
    exit 1
}

if [[ $# -eq 0 ]]; then
    usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
    verify)
        exec bash "$SCRIPT_DIR/logic/flac_verify.sh" "$@"
        ;;
    md5)
        exec bash "$SCRIPT_DIR/logic/flac_md5.sh" "$@"
        ;;
    reencode)
        exec bash "$SCRIPT_DIR/logic/flac_reencode.sh" "$@"
        ;;
    audit)
        exec bash "$SCRIPT_DIR/logic/flac_audit.sh" "$@"
        ;;
    tag-audit)
        exec bash "$SCRIPT_DIR/logic/tag_audit.sh" "$@"
        ;;
    mp3)
        exec bash "$SCRIPT_DIR/logic/mp3_verify.sh" "$@"
        ;;
    verify-gen)
        exec bash "$SCRIPT_DIR/logic/general_verify.sh" "$@"
        ;;
    replaygain)
        exec bash "$SCRIPT_DIR/logic/flac_replaygain.sh" "$@"
        ;;
    batch)
        exec bash "$SCRIPT_DIR/logic/workflow_batch.sh" "$@"
        ;;
    clean)
        exec bash "$SCRIPT_DIR/logic/util_clean.sh" "$@"
        ;;
    check-deps)
        exec bash "$SCRIPT_DIR/logic/util_deps.sh" "$@"
        ;;
    -v|--version)
        echo "Music Suite v${MUSIC_SUITE_VERSION}"
        exit 0
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command '$COMMAND'"
        usage
        ;;
esac