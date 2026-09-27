#!/usr/bin/env bash
set -euo pipefail

HOME_DIR=/home/agent

for dir in "$HOME_DIR/.asdf" "$HOME_DIR/.ssh" "$HOME_DIR/workspace"; do
  mkdir -p "$dir"
  chown agent:agent "$dir"
done

shopt -s nullglob
env_files=(/etc/agentic-container/env.d/*.env)
shopt -u nullglob

for env_file in "${env_files[@]}"; do
  source "$env_file"
done
