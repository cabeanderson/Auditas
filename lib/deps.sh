#!/bin/bash
# Shared definition of dependencies for the music suite.

# List of absolutely required tools for core functionality
REQUIRED_TOOLS=(
    flac
    metaflac
    mp3val
    find
    xargs
    sort
    grep
    awk
    cut
    md5sum
    flock
    ffmpeg
)

# ReplayGain tagging needs exactly one of these; rsgain is the actively
# maintained successor to loudgain and is preferred when both are present.
REPLAYGAIN_TOOLS=(
    rsgain
    loudgain
)

# List of optional tools that enable extra features
OPTIONAL_TOOLS=(
    vbrfixc
    nproc
)

export REQUIRED_TOOLS REPLAYGAIN_TOOLS OPTIONAL_TOOLS