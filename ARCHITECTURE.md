Architecture & Design

This document details the internal design, directory structure, and engineering patterns used in Auditas. It is intended for developers, contributors, and advanced users who want to understand how the toolkit is structured and how the components interact.

Project Structure

Auditas follows a modular design to separate the CLI interface from core logic and shared utilities.

.
├── auditas.sh              # Entry point (Dispatcher)
├── auditas.conf.example    # Configuration template
├── lib/                    # Shared libraries
│   ├── config.sh           # Configuration loader
│   ├── deps.sh             # Dependency definitions
│   ├── lock.sh             # Temporary file and trap management
│   ├── logging.sh          # Standardized colored output
│   ├── parallel.sh         # Parallel execution, counters, progress bars
│   └── utils.sh            # Common helpers
└── logic/                  # Implementation of specific tools
    ├── flac_audit.sh       # Encoder version auditor
    ├── flac_md5.sh         # MD5 scanning and fixing
    ├── flac_reencode.sh    # FLAC re-encoder
    ├── flac_replaygain.sh  # ReplayGain tagging
    ├── flac_verify.sh      # FLAC verification logic
    ├── general_verify.sh   # General audio verification (ffmpeg)
    ├── mp3_verify.sh       # MP3 verification and repair
    ├── tag_audit.sh        # Tag and artwork auditor
    ├── clean.sh            # Cleanup utility
    ├── check_deps.sh       # Dependency checker
    └── workflow_batch.sh   # Orchestrates multiple tools

Design Patterns
1. Dispatcher Pattern

auditas.sh acts as a thin wrapper.

Handles command-line parsing and configuration loading.

Dispatches commands to the corresponding script in logic/.

Allows tools to be developed and tested independently.

2. Parallel Processing

Most tools use parallel execution to maximize CPU and I/O throughput.

Implemented via xargs -P or custom job management in lib/parallel.sh.

Shared counters and progress bars use atomic file operations for thread-safety.

Each parallel job explicitly sources necessary libraries to avoid environment issues.

3. Thread-Safety

Concurrency is managed with file locks (flock) on dedicated file descriptors:

| FD | Purpose |
| :--- | :--- |
| 200 | Logging to shared failure logs |
| 201 | Writing to the verified cache file |
| 202 | Updating progress counters |
| 203 | Writing MD5 missing reports |

This ensures multiple parallel jobs do not overwrite logs or counters.

4. Resume Capability

Long-running tasks (e.g., verify, batch) can resume from last progress.

Uses a set difference algorithm to efficiently skip already-processed files:

```bash
comm -23 <(sort all_files) <(sort verified.log)
```


Time complexity: O(n log n) versus O(n²) for naive per-file checks.

Cached state is stored in ~/.local/state/auditas/state/verified.log.

5. Bit-Perfect Verification

Ensures audio content is unchanged during re-encoding.

Compares MD5 of decoded PCM streams:

```bash
old_md5=$(ffmpeg -i original.flac -f wav - | md5sum)
new_md5=$(ffmpeg -i reencoded.flac -f wav - | md5sum)

[[ "$old_md5" == "$new_md5" ]] && mv reencoded.flac original.flac
```


Guarantees metadata updates or compression changes do not alter audio data.

6. Backup and Safety

Any destructive operation (reencode, md5 --fix, mp3 --fix) creates backups:

*   `backup/` for re-encodes

*   `backup_md5/` for MD5 fixes

*   `.bak` files for MP3 repairs

Ensures recoverability in case of errors or accidental modifications.

7. Configuration Management

Configuration is loaded in order:

1.  `/etc/auditas/config` – system-wide

2.  `~/.config/auditas/config` – user

3.  `./auditas.conf` – local override

Supports environment variable overrides:

```bash
export DEFAULT_JOBS=16
export AUDITAS_BASE=/mnt/data/auditas-data
```


Centralizes defaults like FLAC_COMPRESSION_LEVEL and REPLAYGAIN_TARGET.

8. Logging & Reporting

Centralized via lib/logging.sh.

Provides color-coded output (INFO, WARNING, ERROR).

Persistent logs stored in `~/.local/state/auditas/logs/`.

Reports for verification failures, missing MD5, ReplayGain errors, and batch workflows.

9. Workflow Orchestration

workflow_batch.sh combines multiple steps in a single automated process:

*   FLAC verification

*   MD5 checksum fixes

*   ReplayGain tagging

*   Encoder audit

Supports resume, dry-run, and selective skipping of steps.

10. Adding New Tools

To integrate a new tool into Auditas:

Create the script in logic/.

Source required libraries using relative paths:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
```


Add a case entry in auditas.sh:

```bash
case "$1" in
    newtool) exec "$SCRIPT_DIR/logic/newtool.sh" "${@:2}" ;;
esac
```


Add dependencies to lib/deps.sh if necessary.

11. Performance Considerations

Thread Count (-j) configurable per operation.

Optimized for massive libraries (100K+ files) with minimal memory usage:

*   100K files ≈ 5–10 MB RAM

*   1M files ≈ 50–100 MB RAM

Resume filtering reduces verification time from hours to seconds.

Temporary files stored in /tmp and automatically cleaned.

12. Supported Formats

| Format | Verification / Fixing | Notes |
| :--- | :--- | :--- |
| FLAC | `verify`, `reencode`, `md5`, `audit` | Full bit-perfect checks |
| MP3 | `mp3` | Stream and VBR header repair |
| OGG, Opus, M4A, WAV, AIFF | `verify-gen` | Uses FFmpeg decoding |

13. Key Design Principles

Modularity – Each tool is independent and composable.

Reliability – Bit-perfect checks, safe backups.

Performance – Parallelized and optimized for huge libraries.

Resilience – Resume, logging, and error reporting.

User Safety – Non-destructive operations by default.