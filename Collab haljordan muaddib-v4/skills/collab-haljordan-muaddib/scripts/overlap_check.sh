#!/usr/bin/env bash
# Detect files touched by two branches (or worktrees) since a common base, so two
# agents never edit the same logical file. Uncommitted changes in the current
# worktree are included for the current branch.
# Usage: overlap_check.sh <base> <branch-a> <branch-b>
# Exit 0 when the change sets are disjoint, 1 when they overlap, 2 on usage error.
set -uo pipefail
base="${1:-}"; a="${2:-}"; b="${3:-}"
[[ -z "$base" || -z "$a" || -z "$b" ]] && { echo "usage: overlap_check.sh <base> <branch-a> <branch-b>"; exit 2; }
changed() {
  git diff --name-only "$base...$1" 2>/dev/null
  if [[ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$1" ]]; then
    git status --porcelain 2>/dev/null | awk '{print $NF}'
  fi
}
overlap=$(comm -12 <(changed "$a" | sort -u) <(changed "$b" | sort -u))
if [[ -n "$overlap" ]]; then
  echo "OVERLAP between $a and $b (base $base):"
  echo "$overlap" | sed 's/^/  /'
  exit 1
fi
echo "no overlapping files between $a and $b (base $base)"
