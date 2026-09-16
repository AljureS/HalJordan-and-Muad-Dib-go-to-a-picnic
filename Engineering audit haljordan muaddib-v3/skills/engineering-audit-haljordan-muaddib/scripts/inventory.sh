#!/usr/bin/env bash
# Read-only inventory of a repository to start an audit. Prints file names and
# metadata only. It never opens env or credential files, and by default it prints
# the *names* of package.json scripts, not their commands (commands can embed
# credentials). Pass --commands to print them with KEY=value secrets redacted.
# Usage: inventory.sh [repo-root] [--commands]
set -uo pipefail
root="."; show_cmds=0
for arg in "$@"; do
  case "$arg" in --commands) show_cmds=1 ;; *) root="$arg" ;; esac
done
cd "$root" || exit 1

section() { printf '\n== %s ==\n' "$1"; }

section "git"
git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "not a git repository"
git log --oneline -n 5 2>/dev/null
echo "uncommitted changes: $(git status --short 2>/dev/null | wc -l | tr -d ' ')"

section "top level"
ls -1A

section "agent and tool config"
for p in AGENTS.md CLAUDE.md .claude .agents .codex .cursor .mcp.json .github/workflows; do
  [[ -e "$p" ]] && echo "present: $p"
done
for d in .claude .agents .codex; do
  [[ -d "$d" ]] && find "$d" -maxdepth 4 -type f | sort
done

section "manifests and infra"
ls -1 package.json pnpm-lock.yaml yarn.lock package-lock.json bun.lockb tsconfig.json \
  pyproject.toml requirements.txt go.mod Cargo.toml Dockerfile docker-compose*.yml \
  railway.json railway.toml vercel.json 2>/dev/null

if [[ -f package.json ]]; then
  section "package.json scripts ($([[ $show_cmds -eq 1 ]] && echo 'commands, secrets redacted' || echo 'names only; --commands to show them'))"
  if command -v node >/dev/null 2>&1; then
    node -e 'const p=require("./package.json");for(const [k,v] of Object.entries(p.scripts||{}))console.log(process.argv[1]==="1"?k.padEnd(22)+v:k)' "$show_cmds"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys;p=json.load(open("package.json"));[print(k.ljust(22)+v if sys.argv[1]=="1" else k) for k,v in (p.get("scripts") or {}).items()]' "$show_cmds"
  else
    echo "package.json present; neither node nor python3 available to list scripts safely"
  fi 2>/dev/null | sed -E 's/((TOKEN|SECRET|KEY|PASS(WORD)?|AUTH|CREDENTIAL|COOKIE|SESSION)[A-Za-z0-9_]*=)[^[:space:]]+/\1<redacted>/gI'
fi

section "env files (names only — never open these)"
ls -1 .env* 2>/dev/null || echo "none"

section "size"
if git rev-parse >/dev/null 2>&1; then
  echo "tracked files: $(git ls-files | wc -l | tr -d ' ')"
  git ls-files | sed -nE 's/.*\.([A-Za-z0-9]+)$/\1/p' | sort | uniq -c | sort -rn | head -10
else
  find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' | wc -l
fi
