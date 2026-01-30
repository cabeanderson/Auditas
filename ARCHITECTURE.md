# Architecture & Design

## 📑 Table of Contents

1.  [Project Structure](#-project-structure)
2.  [File Descriptions](#-file-descriptions)
3.  [Configuration](#-configuration)
4.  [Design Patterns](#-design-patterns)
5.  [Adding New Tools](#-adding-new-tools)

##  Project Structure

The project follows a modular design to separate the user interface (CLI) from the core logic and shared utilities.

```text
scripts/
├── music_suite.sh          # Entry point. Dispatches commands to logic/ scripts.
├── music_suite.conf.example # Configuration template.
├── lib/                    # Shared libraries.
│   ├── config.sh           # Loads configuration.
│   ├── deps.sh             # Defines dependency lists.
│   ├── lock.sh             # Manages temporary file cleanup and traps.
│   ├── logging.sh          # Standardized colored output.
│   ├── parallel.sh         # Manages parallel execution, counters, and progress bars.
│   └── utils.sh            # Common helpers (path truncation, hashing).
└── logic/                  # Implementation of specific tools.
    ├── flac_audit.sh       # Encoder version auditor.
    ├── flac_md5.sh         # MD5 scanning and fixing.
    ├── flac_reencode.sh    # FLAC re-encoder.
    ├── flac_replaygain.sh  # ReplayGain tagging.
    ├── flac_verify.sh      # FLAC verification logic.
    ├── general_verify.sh   # General audio verification (ffmpeg).
    ├── mp3_verify.sh       # MP3 verification and repair.
    ├── tag_audit.sh        # Tag and artwork auditor.
    ├── util_clean.sh       # Cleanup utility.
    ├── util_deps.sh        # Dependency checker.
    └── workflow_batch.sh   # Orchestrates multiple tools.
```

## 🧩 Design Patterns

### 1. The Dispatcher Pattern
`music_suite.sh` acts as a thin wrapper. It handles the initial command parsing and `exec`s the corresponding script in `logic/`. This keeps the root directory clean and allows tools to be developed and tested independently.

### 2. Parallel Processing
Most tools utilize `xargs -P` for parallelism to maximize CPU and I/O usage.

*   **State Management**: `lib/parallel_lib.sh` manages a shared counter and total count using atomic file operations.
*   **Environment Isolation**: To avoid issues with function exporting in subshells, the command string passed to `xargs` explicitly sources the required libraries (e.g., `source .../logging.sh`).

### 3. Thread-Safety
Concurrency is managed via `flock` (file locking) on specific file descriptors to prevent race conditions when writing to logs or updating counters:

*   **FD 200** (`$LOG_LOCK`): Logging to shared failure logs.
*   **FD 201** (`$VERIFIED_LOCK`): Writing to the "verified" cache file.
*   **FD 202** (`$COUNTER_LOCK`): Updating the progress counter.

### 4. Resume Capability
Long-running tasks (like verification) support resuming. This is implemented using a set difference algorithm (`comm -23`) between the full file list and the list of already verified files stored in cache logs (e.g., `.flac_verified.log`). This allows the script to skip already-processed files in $O(n \log n)$ time, which is significantly faster than checking files one by one.

## 🛠️ Adding New Tools

To add a new tool to the suite:

1.  Create the script in `logic/`.
2.  Source the necessary libraries using relative paths:
    ```bash
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/logging.sh"
    ```
3.  Add the command to the `case` statement in `music_suite.sh`.
4.  (Optional) Add dependencies to `lib/deps.sh`.