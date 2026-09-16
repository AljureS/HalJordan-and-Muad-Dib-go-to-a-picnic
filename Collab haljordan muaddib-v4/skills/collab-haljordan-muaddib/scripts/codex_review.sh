#!/usr/bin/env bash
# Ask Codex for a non-interactive code review (`codex review`) and capture it as evidence.
# Usage:
#   codex_review.sh --repo <path> (--base <branch> | --commit <sha> | --uncommitted)
#                   [--focus "<what to look at>"] [--out <file>] [--codex-bin <cmd>] [--timeout <s>]
# The review is read-only input for the owner's decision; it never edits files.
set -uo pipefail
repo=""; mode=""; ref=""; focus=""; out=""; codex_bin="codex"; timeout_s=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --base) mode="--base"; ref="$2"; shift 2 ;;
    --commit) mode="--commit"; ref="$2"; shift 2 ;;
    --uncommitted) mode="--uncommitted"; shift ;;
    --focus) focus="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --codex-bin) codex_bin="$2"; shift 2 ;;
    --timeout) timeout_s="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$repo" || -z "$mode" ]] && { echo "usage: codex_review.sh --repo <path> (--base <branch> | --commit <sha> | --uncommitted) [--focus ...]" >&2; exit 2; }
repo="$(cd "$repo" && pwd)" || exit 2
read -r -a codex_cmd <<< "$codex_bin"
command -v "${codex_cmd[0]}" >/dev/null 2>&1 || [[ -x "${codex_cmd[0]}" ]] || { echo "codex not found" >&2; exit 2; }
stamp="$(date -u +%Y%m%dT%H%M%SZ)"; rec_dir="$repo/.collab/reviews"; mkdir -p "$rec_dir"
[[ -z "$out" ]] && out="$rec_dir/$stamp-review.md"
args=(review "$mode"); [[ -n "$ref" ]] && args+=("$ref"); [[ -n "$focus" ]] && args+=("$focus")
runner=(); [[ -n "$timeout_s" ]] && { command -v timeout >/dev/null 2>&1 && runner=(timeout "$timeout_s"); }
sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
{
  echo "# Codex review — $stamp"; echo; echo "repo: $repo"; echo "HEAD: $sha"; echo "target: $mode ${ref:-}"; [[ -n "$focus" ]] && echo "focus: $focus"; echo
  ( cd "$repo" && "${runner[@]}" "${codex_cmd[@]}" "${args[@]}" ) 2>&1
  echo; echo "exit code: ${PIPESTATUS[0]:-?}"
} | tee "$out"
rc=${PIPESTATUS[0]}
echo "review saved: $out (input to the owner's decision, not a verdict)"
exit 0
