#!/bin/bash
# Bash completion for auditas.sh

# Copyright (C) 2026 Cabe Anderson
# SPDX-License-Identifier: GPL-3.0-or-later

_auditas_completion() {
    local cur prev words cword
    # Use bash-completion helper if available, otherwise fallback
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    fi

    # Handle -j value completion (suggest core counts)
    if [[ "$prev" == "-j" ]]; then
        local nproc_val
        nproc_val=$(nproc 2>/dev/null || echo 4)
        COMPREPLY=( $(compgen -W "2 4 8 16 $nproc_val" -- "$cur") )
        return
    fi

    local commands="verify v md5 reencode audit tag-audit mp3 verify-gen replaygain batch clean check-deps help"
    
    # Find the subcommand (first argument after the script name)
    local command=""
    local i
    for (( i=1; i < cword; i++ )); do
        if [[ " ${commands} " =~ " ${words[i]} " ]]; then
            command="${words[i]}"
            break
        fi
    done

    # If no command found yet, complete commands
    if [[ -z "$command" ]]; then
        if [[ $cword -eq 1 ]]; then
            COMPREPLY=( $(compgen -W "${commands}" -- "$cur") )
        fi
        return
    fi

    # If we are completing options for a specific command
    case "$command" in
        verify|v)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "-f -j -r -m --no-md5 --clear-cache -h --help" -- "$cur") )
            fi
            ;;
        md5)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--fix -j -h --help" -- "$cur") )
            fi
            ;;
        reencode)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "-j -h --help" -- "$cur") )
            fi
            ;;
        audit)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "-j --strict --output -h --help" -- "$cur") )
            fi
            ;;
        tag-audit)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "-j --output --html --no-embedded-check -h --help" -- "$cur") )
            fi
            ;;
        mp3)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "-j --fix -h --help" -- "$cur") )
            fi
            ;;
        verify-gen)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "-j -h --help" -- "$cur") )
            fi
            ;;
        replaygain)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "-j --dry-run -h --help" -- "$cur") )
            fi
            ;;
        batch)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--dry-run --force --resume --skip-verify --skip-md5 --skip-replaygain --skip-audit --parallel-dirs --auto-discover -h --help" -- "$cur") )
            fi
            ;;
        clean|check-deps|help)
            ;;
    esac
    
    # Fallback to file completion if no options generated
    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        if declare -F _filedir >/dev/null 2>&1; then
            _filedir
        else
            COMPREPLY=( $(compgen -f -- "$cur") )
        fi
    fi
}

complete -F _auditas_completion auditas.sh
complete -F _auditas_completion ./auditas.sh
complete -F _auditas_completion auditas