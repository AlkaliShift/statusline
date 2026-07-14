#!/bin/sh
# Claude Code statusLine command
# Displays: cwd | model | git branch (if in a repo)

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "unknown"')
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')

# Shorten home directory to ~
home="$HOME"
if [ -n "$home" ]; then
  cwd=$(echo "$cwd" | sed "s|^$home|~|")
fi

# Get git branch without acquiring locks
branch=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

if [ -n "$branch" ]; then
  printf "%s  |  %s  |  %s" "$cwd" "$model" "$branch"
else
  printf "%s  |  %s" "$cwd" "$model"
fi
