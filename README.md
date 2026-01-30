# Music Library Management Suite

A Bash toolkit for verifying, repairing, and managing digital music libraries. Built for audiophiles and archivists handling very large collections. Made with Claude and Gemini.

## Features

- **FLAC Integrity**: Parallel verification, MD5 management, and encoder auditing.
- **Multi-Format**: Support for MP3 (VBR fix), OGG, Opus, M4A, WAV, and AIFF.
- **Quality Control**: ReplayGain (R128) tagging and metadata/cover art auditing.
- **Performance**: Optimized for massive libraries with O(n log n) resume capability.
- **Linux Standard**: Follows XDG Base Directory specification and FHS.

## Installation

```bash
git clone https://github.com/cabeanderson/music-suite.git
cd music-suite

# Install system-wide
sudo make install

# Verify
music-suite --version
music-suite check-deps
```

## Commands

### verify - FLAC Verification

Comprehensive parallel FLAC integrity checking.

```bash
./music_suite.sh verify [OPTIONS] [path]

Options:
  -f              Enable FFmpeg full decode check (slower, more thorough)
  -j jobs         Number of parallel jobs (default: nproc)
  -r              Resume mode - skip previously verified files
  -m, --no-md5    Disable MD5 missing check
  --clear-cache   Clear verification cache

Examples:
  verify /music                    # Basic verification
  verify -f -j 8 /music           # FFmpeg check with 8 threads
  verify -r /music                # Resume interrupted verification
```

**Performance:** ~100-500 files/second (FLAC mode), ~20-100 files/second (FFmpeg mode)

**Output:**
- Real-time progress with counters
- Failure log with detailed error messages
- MD5 missing report (per-folder)

### md5 - MD5 Checksum Management

Detect and fix missing FLAC MD5 checksums.

```bash
./music_suite.sh md5 [--fix] [-j jobs] [directory]

Options:
  --fix     Re-encode files to add MD5 checksums (creates backups)
  -j jobs   Number of parallel jobs

Examples:
  md5 /music              # Scan for missing MD5
  md5 --fix /music        # Fix by re-encoding
```

**How it works:**
1. Scans first track of each album
2. Identifies albums with missing MD5 signatures
3. In fix mode: re-encodes all files in affected albums
4. Verifies bit-perfect audio via MD5 comparison
5. Moves originals to `backup_md5/` folders

### audit - Encoder Version Audit

Quick check of encoder versions and integrity for first tracks.

```bash
./music_suite.sh audit [OPTIONS]

Options:
  -j jobs     Number of parallel jobs
  --strict    Strict version checking:
              Green:  1.3.0+
              Yellow: 1.2.x
              Red:    <1.2.0, non-reference, or unknown
  --output FILE   Save files needing attention to FILE

Examples:
  audit                    # Quick audit
  audit --strict          # Strict version rules
  audit --output old.txt  # Save list of old encodings
```

### reencode - Re-encode Current Folder

Re-encode all FLAC files in the current directory with verification.

```bash
./music_suite.sh reencode [-j jobs]

Examples:
  cd /music/album
  music_suite.sh reencode
```

**Process:**
1. Scans and reports current state
2. Asks for confirmation
3. Re-encodes with FLAC -8 (best compression)
4. Verifies bit-perfect audio via MD5
5. Moves originals to `backup/`

### mp3 - MP3 Integrity & Repair

Scan and fix MP3 files using mp3val and vbrfixc.

```bash
./music_suite.sh mp3 [--fix] [-j jobs] [directory]

Options:
  --fix     Repair detected issues (creates .bak files)
  -j jobs   Number of parallel jobs

Examples:
  mp3 /music              # Scan for issues
  mp3 --fix /music        # Fix issues
```

**Fixes:**
- Stream errors (mp3val)
- Missing/corrupt VBR headers (vbrfixc)

### verify-gen - Multi-Format Verification

Verify OGG, Opus, M4A, WAV, and AIFF files using FFmpeg.

```bash
./music_suite.sh verify-gen [-j jobs] [directory]

Examples:
  verify-gen /music
```

### replaygain - ReplayGain Tagging

Apply R128 ReplayGain tags to FLAC albums.

```bash
./music_suite.sh replaygain [OPTIONS] [path]

Options:
  -j jobs      Number of parallel jobs
  --dry-run    Show what would be done without modifying

Examples:
  replaygain /music              # Tag all albums
  replaygain --dry-run /music    # Preview changes
```

**Features:**
- Idempotent (skips already-tagged albums)
- Album and track gain modes
- Target loudness: -18 LUFS
- No-clip protection

### tag-audit - Tag & Artwork Quality

Audit library for missing tags, cover art issues, and inconsistencies.

```bash
./music_suite.sh tag-audit [OPTIONS] [directory]

Options:
  -j jobs              Number of parallel jobs
  --output FILE        Write detailed report to FILE
  --no-embedded-check  Skip embedded cover art check (faster)

Examples:
  tag-audit /music                    # Full audit
  tag-audit --output issues.txt       # Save report
  tag-audit --no-embedded-check       # Fast mode
```

**Checks:**
- Missing essential tags (Artist, Album, Title, Date, etc.)
- Cover art presence and quality (resolution, aspect ratio)
- Tag consistency within albums
- Embedded vs folder cover art

**Severity Levels:**
- **CRITICAL:** Missing Artist, Album, or Title
- **WARNING:** Missing Date, Track#, Album Artist, Cover Art
- **INFO:** Missing Genre, formatting issues

### batch - Batch Workflow Orchestrator

Run a comprehensive workflow on one or more directories.

```bash
./music_suite.sh batch [OPTIONS] [directory...]

Workflow Steps:
  1. Verify FLAC integrity
  2. Fix missing MD5 checksums
  3. Apply ReplayGain tags
  4. Audit encoder versions

Options:
  --dry-run           Show what would be done
  --force             Skip all confirmations
  --resume            Resume from last completed step
  --skip-verify       Skip FLAC verification
  --skip-md5          Skip MD5 fixes
  --skip-replaygain   Skip ReplayGain
  --skip-audit        Skip encoder audit

Examples:
  batch /music                     # Full workflow
  batch --dry-run /music          # Preview
  batch --skip-audit /music       # Skip encoder audit
  batch /music/A /music/B         # Multiple directories
```

**Features:**
- Pre-flight checks (disk space, file counts)
- Quick analysis (estimates work needed)
- Error collection and summary
- Resume capability on failure
- Continues on non-critical errors

### clean - Cleanup Backups

Remove temporary backup files and directories.

```bash
./music_suite.sh clean

Removes:
  - backup/ directories
  - backup_md5/ directories
  - *.bak files
  - *.vbr.bak files
  - tmp_* files
```

### check-deps - Dependency Checker

Verify all required and optional tools are installed.

```bash
./music_suite.sh check-deps
```

## Configuration

Configuration is loaded in the following order:
1. `/etc/music_suite/config` (System-wide)
2. `~/.config/music_suite/config` (User)
3. `./music_suite.conf` (Local override)

```bash
# Example ~/.config/music_suite/config

# Parallel job settings
DEFAULT_JOBS=8

# FLAC re-encoding compression level (0-8, 8 is best)
FLAC_COMPRESSION_LEVEL=8

# ReplayGain target loudness in LUFS
REPLAYGAIN_TARGET=-18

# You can override the default base directory if needed.
# MUSIC_SUITE_BASE=~/.my_other_music_suite
```

### Environment Variables

Alternatively, set environment variables, which take precedence over the configuration file:

```bash
export DEFAULT_JOBS=16
export MUSIC_SUITE_BASE=/mnt/data/music-suite-data
```

## Common Workflows

### Initial Library Setup

```bash
# 1. Full verification with FFmpeg
./music_suite.sh verify -f -j $(nproc) /music

# 2. Fix any missing MD5 checksums
./music_suite.sh md5 --fix /music

# 3. Apply ReplayGain to all albums
./music_suite.sh replaygain /music

# 4. Audit for tag quality issues
./music_suite.sh tag-audit /music
```

### Regular Maintenance

```bash
# Weekly: Quick verification (resume mode)
./music_suite.sh verify -r /music

# Monthly: Full batch workflow
./music_suite.sh batch /music
```

### New Music Added

```bash
# Run batch workflow on new directory
./music_suite.sh batch /music/new_albums

# Or use auto-discovery
./music_suite.sh batch --auto-discover /music
```

### Troubleshooting Corrupt Files

```bash
# 1. Verify and identify issues
./music_suite.sh verify -f /music

# 2. Check failed files log
cat flac_failures_*.log

# 3. Test specific file
flac -t problematic_file.flac
ffmpeg -v error -i problematic_file.flac -f null -
```

### Preparing for Backup

```bash
# 1. Verify everything is intact
./music_suite.sh verify -f /music

# 2. Ensure all have MD5 checksums
./music_suite.sh md5 /music

# 3. Check tag quality
./music_suite.sh tag-audit /music

# 4. Clean up temporary files
./music_suite.sh clean
```

## Advanced Usage

### Massive Libraries (100K+ Files)

The suite is optimized for very large collections:

```bash
# Initial verification
./music_suite.sh verify -j $(nproc) /huge-library

# If interrupted, resume is extremely fast
./music_suite.sh verify -r /huge-library
# Resume filtering: ~2 seconds for 100K files (vs 45+ min with naive approach)
```

**Memory usage:** ~50-100 bytes per file
- 100K files ≈ 5-10 MB RAM
- 1M files ≈ 50-100 MB RAM

### Automation & Scheduling

```bash
# Weekly verification cron job
0 2 * * 0 /path/to/music_suite.sh verify -r /music >> /var/log/music-verify.log 2>&1

# Email on failures
./music_suite.sh verify /music || mail -s "Verification failed" user@example.com < flac_failures_*.log

# Batch multiple directories
for dir in /music/{A..Z}; do
    ./music_suite.sh verify "$dir"
done
```

### Performance Tuning

**Thread Count:**
```bash
# Maximum speed
-j $(nproc)

# Conservative (low impact)
-j 2

# Balanced
-j $(($(nproc) / 2))
```

**For Network/Slow Drives:**
```bash
# Reduce threads to avoid overwhelming I/O
-j 4
```

## Output & Logs

By default, persistent data is stored in standard XDG locations.

### Log Files (`~/.local/state/music_suite/logs/`)
- `flac_failures_*.log`: Failed files from `verify` with error details.
- `flac_missing_md5_*.log`: Folders with files missing MD5 checksums.
- `batch_workflow_*.log`: Full details from the `batch` command.
- `batch_errors_summary_*.log`: A summary of errors from the `batch` command.
- `replaygain_errors_*.log`: Failures from the `replaygain` command.
- `general_failures_*.log`: Failures from the `verify-gen` command.

### Cache Files (`~/.cache/music_suite/`)
- `flac_verified.log`: A list of successfully verified FLAC files, used for the `verify --resume` feature.
- `general_verified.log`: Cache for `verify-gen --resume`.

### State Files (`~/.local/state/music_suite/state/`)
- `batch_workflow_state`: Stores the progress of the `batch` command, used for the `batch --resume` feature.

### Temporary Files
- Lock files (e.g., `/tmp/flac_log_$$.lock`) are created in `/tmp` during execution and are cleaned up automatically on exit.

## Troubleshooting

### Common Issues

**"Command not found" errors:**
```bash
# Check dependencies
./music_suite.sh check-deps

# Install missing tools
sudo apt install flac ffmpeg mp3val
```

**Slow verification:**
```bash
# Reduce thread count
-j 2

# Disable FFmpeg check
# (remove -f flag)

# Skip MD5 check
--no-md5
```

**Resume not working:**
```bash
# Clear cache and restart
./music_suite.sh verify --clear-cache
./music_suite.sh verify /music
```

**Permission denied:**
```bash
# Make scripts executable
chmod +x music_suite.sh logic/*.sh

# Check file ownership
ls -la /music
```

**Out of disk space:**
```bash
# Clean backups before re-encoding
./music_suite.sh clean

# Check space
df -h /music
```

## Technical Details

### Thread Safety

All parallel operations use dedicated lock files per resource:
- **FD 200** - Failure log writes
- **FD 201** - Verified cache writes
- **FD 202** - Progress counter updates
- **FD 203** - MD5 report writes

### Resume Optimization

Uses `sort` + `comm` for O(n log n) bulk filtering instead of O(n²) per-file grep:

```bash
# Old approach: check each file individually (slow)
for file in $files; do grep "$file" verified.log; done  # O(n²)

# New approach: bulk set difference (fast)
comm -23 <(sort all_files) <(sort verified.log)  # O(n log n)
```

**Result:** ~3000x faster for 100K files (45min → 2sec)

### Bit-Perfect Verification

When re-encoding, audio integrity is verified by comparing MD5 hashes of decoded audio:

```bash
old_md5=$(ffmpeg -i original.flac -f wav - | md5sum)
new_md5=$(ffmpeg -i reencoded.flac -f wav - | md5sum)

# Only replace if identical
[[ "$old_md5" == "$new_md5" ]] && mv reencoded.flac original.flac
```

## Project Structure

```text
.
├── music_suite.sh          # Main entry point
├── music-suite.1           # Man page
├── music_suite_completion.bash # Bash completion script
├── music_suite.conf.example # Configuration template
├── Makefile                # Installation script
├── LICENSE.md              # License file
├── CHANGELOG.md            # Version history
├── ARCHITECTURE.md         # Technical design docs
├── lib/                    # Shared libraries
│   ├── config.sh           # Configuration loader
│   ├── deps.sh             # Dependency definitions
│   ├── lock.sh             # Temp file management
│   ├── logging.sh          # Colored output
│   ├── parallel.sh         # Parallel processing
│   └── utils.sh            # Utility functions
└── logic/                  # Tool implementations
    ├── flac_audit.sh       # Encoder auditor
    ├── flac_md5.sh         # MD5 management
    ├── flac_reencode.sh    # FLAC re-encoder
    ├── flac_replaygain.sh  # ReplayGain tagger
    ├── flac_verify.sh      # FLAC verifier
    ├── general_verify.sh   # Multi-format verifier
    ├── mp3_verify.sh       # MP3 tools
    ├── tag_audit.sh        # Tag quality auditor
    ├── util_clean.sh       # Cleanup utility
    ├── util_deps.sh        # Dependency checker
    └── workflow_batch.sh   # Workflow orchestrator
```

## Contributing

Contributions welcome! Areas for improvement:

- Additional audio format support
- GUI/Web interface
- Database backend for tracking history
- Integration with music databases (MusicBrainz, etc.)
- Additional tag validation rules

## License

GNU General Public License v3.0 (GPLv3)

## Credits

Built for managing large-scale digital music archives with:
- Bash scripting and parallel processing
- FLAC reference tools
- FFmpeg for multi-format support
- mp3val and vbrfixc for MP3 integrity
- loudgain for ReplayGain tagging

## Support

For issues or questions:
- Check the troubleshooting section
- Review `--help` for individual commands
- Check dependency requirements with `check-deps`

## Changelog

### Version 1.0.0 (2026-01-30)
- Initial release
- FLAC verification with resume capability
- MD5 checksum management
- MP3 integrity checking and VBR repair
- Multi-format audio verification
- ReplayGain tagging
- Tag quality auditing
- Batch workflow orchestration
- Optimized for massive libraries

---

**Made for music lovers and archivists**