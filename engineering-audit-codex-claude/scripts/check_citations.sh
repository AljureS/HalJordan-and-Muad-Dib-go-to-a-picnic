#!/usr/bin/env bash
# Verifies that every `path:line` (or `path:line-line`) citation in a Markdown
# report points to an existing file and a line inside it.
# Usage: scripts/check_citations.sh <report.md> [repo-root]
# Exit 0 when every citation resolves, 1 otherwise.
set -uo pipefail
report="${1:?usage: check_citations.sh <report.md> [repo-root]}"
root="${2:-.}"
[[ -f "$report" ]] || { echo "report not found: $report"; exit 1; }

total=0; bad=0
while IFS= read -r cite; do
  [[ -z "$cite" ]] && continue
  total=$((total + 1))
  path="${cite%:*}"
  line="${cite##*:}"; line="${line%%-*}"
  file="$root/$path"
  if [[ ! -f "$file" ]]; then
    echo "MISSING FILE  $cite"; bad=$((bad + 1)); continue
  fi
  n=$(awk 'END{print NR}' "$file")
  if (( line < 1 || line > n )); then
    echo "BAD LINE      $cite (file has $n lines)"; bad=$((bad + 1))
  fi
done < <(
  sed -E 's#[A-Za-z]+://[^ )>`]+##g' "$report" \
  | grep -oE '[A-Za-z0-9_./@-]+\.[A-Za-z0-9]+:[0-9]+(-[0-9]+)?' \
  | sed -E 's#^\./##' \
  | grep -vE '^[0-9.]+:' \
  | sort -u
)
echo "checked $total citations, $bad problems"
(( bad == 0 ))
