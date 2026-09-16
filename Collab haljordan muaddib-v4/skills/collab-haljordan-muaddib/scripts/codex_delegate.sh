#!/usr/bin/env bash
# Delegate one bounded task to Codex non-interactively (`codex exec`) from Claude Code's Bash,
# and come back with evidence: exit code, Codex's last message, files changed since the base
# commit, and a delegation record. Never commits, never pushes, never touches auth.
#
# Usage:
#   codex_delegate.sh --repo <path> (--task "<text>" | --task-file <brief.md>)
#                     [--model <slug>] [--effort minimal|low|medium|high|xhigh]
#                     [--sandbox workspace-write|read-only] [--out <file>] [--json]
#                     [--resume] [--allow-dirty] [--timeout <seconds>] [--codex-bin <cmd>]
#                     [--check-usage --account-alias <alias> --reserve <pct>]
#
# Notes: --resume continues Codex's last session (`codex exec resume --last`), which keeps
# the context but not the flags; --check-usage reads the Codex account limits first and stops
# when the account is blocked under the reserve policy (see usage_decide.py).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo=""; task=""; task_file=""; model=""; effort=""; sandbox="workspace-write"; out=""; json=0
resume=0; allow_dirty=0; timeout_s=""; codex_bin="codex"; check_usage=0; alias="unknown"; reserve="15"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --task) task="$2"; shift 2 ;;
    --task-file) task_file="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --effort) effort="$2"; shift 2 ;;
    --sandbox) sandbox="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --resume) resume=1; shift ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --timeout) timeout_s="$2"; shift 2 ;;
    --codex-bin) codex_bin="$2"; shift 2 ;;
    --check-usage) check_usage=1; shift ;;
    --account-alias) alias="$2"; shift 2 ;;
    --reserve) reserve="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$repo" ]] && { echo "--repo is required" >&2; exit 2; }
[[ -n "$task_file" ]] && task="$(cat "$task_file")"
[[ -z "$task" ]] && { echo "--task or --task-file is required" >&2; exit 2; }
case "$sandbox" in workspace-write|read-only) ;; *) echo "refusing sandbox '$sandbox': only workspace-write or read-only are allowed for delegation" >&2; exit 2 ;; esac
repo="$(cd "$repo" && pwd)" || { echo "repo not found: $repo" >&2; exit 2; }
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repository: $repo" >&2; exit 2; }
read -r -a codex_cmd <<< "$codex_bin"
command -v "${codex_cmd[0]}" >/dev/null 2>&1 || [[ -x "${codex_cmd[0]}" ]] || { echo "codex not found: ${codex_cmd[0]} (npm install -g @openai/codex && codex login)" >&2; exit 2; }

dirty="$(git -C "$repo" status --short)"
if [[ -n "$dirty" && $allow_dirty -eq 0 ]]; then
  echo "working tree has uncommitted changes; commit/stash them or pass --allow-dirty (attribution of Codex's edits becomes unreliable):" >&2
  echo "$dirty" >&2; exit 3
fi

if [[ $check_usage -eq 1 ]]; then
  tmpu="$(mktemp -d)"
  if python3 "$here/codex_usage_read.py" > "$tmpu/raw.json" 2>"$tmpu/err"; then
    python3 "$here/usage_normalize.py" --provider openai --account-alias "$alias" "$tmpu/raw.json" > "$tmpu/norm.json"
    python3 "$here/usage_decide.py" --records "$tmpu/norm.json" --reserve "$reserve" --provider openai > "$tmpu/dec.json" 2>/dev/null
    if grep -q '"verdict": "blocked"' "$tmpu/dec.json"; then
      echo "usage check: Codex account '$alias' is BLOCKED under reserve ${reserve}% — not delegating"; cat "$tmpu/dec.json"; rm -rf "$tmpu"; exit 4
    fi
    echo "usage check: $(grep -o '"verdict": "[a-z_]*"' "$tmpu/dec.json" | sort -u | tr '\n' ' ')"
  else
    echo "usage check: unknown (reader failed: $(head -1 "$tmpu/err")) — proceeding, quota not verified"
  fi
  rm -rf "$tmpu"
fi

base_sha="$(git -C "$repo" rev-parse HEAD)"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
rec_dir="$repo/.collab/delegations"; mkdir -p "$rec_dir"
[[ -z "$out" ]] && out="$rec_dir/$stamp-last-message.md"

args=(exec)
if [[ $resume -eq 1 ]]; then args+=(resume --last); fi
args+=(--sandbox "$sandbox" --output-last-message "$out")
[[ -n "$model" ]] && args+=(--model "$model")
[[ -n "$effort" ]] && args+=(-c "model_reasoning_effort=\"$effort\"")
[[ $json -eq 1 ]] && args+=(--json)
args+=("$task")

runner=()
if [[ -n "$timeout_s" ]]; then
  if command -v timeout >/dev/null 2>&1; then runner=(timeout "$timeout_s"); elif command -v gtimeout >/dev/null 2>&1; then runner=(gtimeout "$timeout_s"); else echo "note: no timeout binary; running without a time limit" >&2; fi
fi

echo "delegating to Codex in $repo (base $base_sha, sandbox $sandbox${model:+, model $model}${effort:+, effort $effort})"
log="$rec_dir/$stamp-stdout.log"
( cd "$repo" && "${runner[@]}" "${codex_cmd[@]}" "${args[@]}" ) > "$log" 2>&1
rc=$?

changed="$(git -C "$repo" status --short)"
diffstat="$(git -C "$repo" diff --stat | tail -1)"
python3 - "$rec_dir/$stamp-delegation.json" "$base_sha" "$rc" "$out" "$log" "$sandbox" "$model" "$effort" "$resume" "$changed" << 'PY'
import json, sys
p, base, rc, out, log, sandbox, model, effort, resume, changed = sys.argv[1:]
json.dump({"base_sha": base, "exit_code": int(rc), "last_message_file": out, "stdout_log": log, "sandbox": sandbox,
           "model": model or None, "effort": effort or None, "resumed": resume == "1",
           "files_changed": [l[3:] for l in changed.splitlines() if l.strip()],
           "committed": False, "note": "Codex's edits are uncommitted; review the diff, run the tests, then commit yourself."}, open(p, "w"), indent=2)
PY

echo "== result =="
echo "exit code: $rc"
echo "last message: $out"
echo "files changed since $base_sha:"; if [[ -n "$changed" ]]; then echo "$changed" | sed 's/^/  /'; else echo "  (none)"; fi
[[ -n "$diffstat" ]] && echo "diffstat: $diffstat"
echo "record: $rec_dir/$stamp-delegation.json"
echo "== last message (tail) =="; tail -n 20 "$out" 2>/dev/null || echo "(no last message captured; see $log)"
exit "$rc"
