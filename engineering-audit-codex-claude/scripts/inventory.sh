#!/usr/bin/env bash
# Read-only inventory of a repository to start an audit. Prints names and
# metadata only — never the contents of env or credential files.
# Usage: scripts/inventory.sh [repo-root]
set -uo pipefail
cd "${1:-.}" || exit 1

section() { printf '\n== %s ==\n' "$1"; }

section "git"
git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "not a git repository"
git log --oneline -n 5 2>/dev/null
dirty=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
echo "uncommitted changes: ${dirty:-0}"

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
  section "package.json scripts"
  if command -v node >/dev/null 2>&1; then
    node -e 'const p=require("./package.json");for(const [k,v] of Object.entries(p.scripts||{}))console.log(k.padEnd(22),v)'
  else
    grep -A40 '"scripts"' package.json
  fi
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
