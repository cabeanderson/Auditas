# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - 2026-07-26

### Added
- `reencode` now accepts a directory argument (`auditas reencode /path`) instead of requiring `cd` into the album folder first.
- ReplayGain tagging now supports `rsgain` (the actively maintained successor to `loudgain`) in addition to `loudgain`, auto-detected on PATH with `REPLAYGAIN_TOOL=` as an explicit override.

### Fixed
- `md5 --fix` crashed with `xargs: invalid number ""` whenever `-j` wasn't passed explicitly — the job count was never defaulted.
- `reencode`'s file-count summary (`((ok_count++))`) silently aborted the script under `set -e` as soon as the counter incremented from 0.
- `reencode` built temp filenames as `tmp_./file.flac`, which `flac` read as a nonexistent `tmp_.` subdirectory — every re-encode failed.
- `-h`/`--help` crashed with `command not found` on `mp3`, `audit`, and `reencode` because the logging library was sourced after the argument-parsing loop that could call it.
- `DEFAULT_JOBS` from the config file was silently ignored (only `-j` worked) on `mp3`, `tag-audit`, `audit`, and `reencode`, because the job-count default was computed before the config file was loaded.
- `flac_replaygain.sh` tried to `export -a` bash arrays to parallel worker subprocesses; bash silently drops exported arrays across `exec`, so the "remove stale ReplayGain tags before rescanning" step was a no-op. Array data is now baked into the worker command string instead.
- `REPLAYGAIN_TARGET` was computed but never actually passed to the scanning tool, so custom loudness targets had no effect on the scan itself.
- `batch` was completely broken — `workflow_batch.sh` contained two corrupted, concatenated copies of the same script (stray `}` in place of `done`, unclosed `if`, top-level `local` outside any function) and failed to parse at all.

## [1.0.0] - 2026-01-30

### Changed
- Renamed project from "Music Suite" to "Auditas"
- Updated all command references and configuration paths

### Added
- Initial release
- FLAC verification with resume capability
- MD5 checksum management
- MP3 integrity checking and VBR repair
- Multi-format audio verification
- ReplayGain tagging
- Tag quality auditing
- Batch workflow orchestration
- Optimized for massive libraries (1M+ files)
- Centralized data storage in `~/.local/share/auditas` (logs, cache, state)