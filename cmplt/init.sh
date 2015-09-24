#!/bin/bash

# load web completions

if [ -n "$BASH_VERSION" ]; then
  root=$(dirname "${BASH_SOURCE[0]}")
  source "$root/completion.bash"

elif [ -n "$ZSH_VERSION" ]; then
  root=$(dirname "$0")
  source "$root/completion.zsh"

fi
