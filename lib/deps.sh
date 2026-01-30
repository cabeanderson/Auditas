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
    loudgain
)

# List of optional tools that enable extra features
OPTIONAL_TOOLS=(
    vbrfixc
    nproc
)

export REQUIRED_TOOLS OPTIONAL_TOOLS