# Auditas

## Features

### Audio Integrity & Repair

- **FLAC Verification** – Detect corruption, truncation, and checksum errors
- **MD5 Management** – Identify and safely fix missing FLAC MD5 checksums
- **MP3 Repair** – Detect and fix stream errors and VBR header issues
- **Multi-Format Verification** – Validate OGG, Opus, M4A, WAV, and AIFF

### Library Quality

- **ReplayGain (R128)** – Album and track loudness tagging
- **Tag & Artwork Audit** – Find missing metadata and low-quality covers
- **Encoder Audit** – Identify outdated or non-reference FLAC encoders

### Performance & Safety

- Parallel processing for large libraries
- Resume support for interrupted scans
- Batch workflows for unattended maintenance
- Non-destructive repairs with automatic backups
- Detailed logs and reports

## Installation

Clone and install system-wide:

```bash
git clone https://github.com/cabeanderson/auditas.git
cd auditas
sudo make install
```

Verify installation and dependencies:

```bash
auditas --version
auditas check-deps
```

> **Note**
> `check-deps` verifies required tools such as `flac`, `ffmpeg`, `mp3val`, and `vbrfixc`.

## Quick Start

Scan a music library for FLAC issues:

```bash
auditas verify /music
```

Run a full integrity check with parallel jobs:

```bash
auditas verify -f -j 8 /music
```

Fix missing FLAC MD5 checksums:

```bash
auditas md5 --fix /music
```

## Common Commands

### Verify FLAC Files
```bash
auditas verify /music
auditas verify -f -j 8 /music
auditas verify -r /music
```

Provides real-time progress and logs failures only.

### Manage FLAC MD5 Checksums
```bash
auditas md5 /music
auditas md5 --fix /music
```

### Audit FLAC Encoders
```bash
auditas audit
auditas audit --strict
auditas audit --output old_encoders.txt
```

### Re-encode FLAC Albums

Safely re-encode all files in the current directory:

```bash
cd /music/Album
auditas reencode
```

### MP3 Integrity & Repair
```bash
auditas mp3 /music
auditas mp3 --fix /music
```

### Verify Other Formats
```bash
auditas verify-gen /music
```

Supports OGG, Opus, M4A, WAV, and AIFF.

### ReplayGain Tagging (R128)
```bash
auditas replaygain /music
auditas replaygain --dry-run /music
```

### Tag & Artwork Audit
```bash
auditas tag-audit /music
auditas tag-audit --output issues.txt
auditas tag-audit --no-embedded-check
```

### Batch Workflow

Run a full maintenance pass automatically:

```bash
auditas batch /music
auditas batch --dry-run /music
```

Orchestrates a full maintenance workflow. Offers advanced options for resuming, skipping steps, and parallel processing. Use `auditas batch --help` for details.

Includes:

- FLAC verification
- MD5 repair

### Cleanup (`clean`)

Remove temporary and backup files:

```bash
auditas clean
```

## Configuration

Auditas reads configuration in the following order:

1. `/etc/auditas/config`
2. `~/.config/auditas/config`
3. `./auditas.conf` (local override)

Example configuration:

```bash
DEFAULT_JOBS=8
FLAC_COMPRESSION_LEVEL=8
REPLAYGAIN_TARGET=-18
```

Environment variables override config values:

```bash
export DEFAULT_JOBS=16
export AUDITAS_BASE=/mnt/data/auditas
```

## Recommended Workflows

### Initial Library Setup
```bash
auditas verify -f /music
auditas md5 --fix /music
auditas replaygain /music
auditas tag-audit /music
```

### Weekly Maintenance
```bash
auditas verify -r /music
```

### Monthly Full Maintenance
```bash
auditas batch /music
```

### Adding New Music
```bash
auditas batch /music/new_albums
```

## Logs & Reports

Auditas follows the XDG Base Directory specification:

- **Logs:** `~/.local/state/auditas/logs/`
- **Cache:** `~/.cache/auditas/`
- **State:** `~/.local/state/auditas/state/`

Logs include failure reports, batch summaries, and ReplayGain errors.

## Troubleshooting

- **Missing dependencies:** `auditas check-deps`
- **Slow scans:** reduce threads (`-j 2`) or disable full decode
- **Resume problems:** clear cache (`--clear-cache`)
- **Permission errors:** ensure scripts are executable
- **Low disk space:** run `auditas clean` before re-encoding

## License

Auditas is licensed under the GNU GPL v3.0.

Built for people who care about their music—and want it to last.