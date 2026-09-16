#!/usr/bin/env bash
# Stand-in for the `codex` CLI used by the tests. Logs its argv to $FAKE_CODEX_LOG.
printf '%s\n' "$@" > "${FAKE_CODEX_LOG:-/tmp/fake_codex.log}"
out=""; prev=""
for a in "$@"; do [[ "$prev" == "--output-last-message" ]] && out="$a"; prev="$a"; done
if [[ "$1" == "exec" ]]; then
  [[ "${FAKE_CODEX_TOUCH:-}" == "1" ]] && printf 'edited by fake codex\n' >> src/app.ts
  [[ -n "$out" ]] && printf 'Done: refactored src/app.ts as asked.\n' > "$out"
  echo "turn completed"; exit "${FAKE_CODEX_EXIT:-0}"
elif [[ "$1" == "review" ]]; then
  echo "Review: no blocking issues; consider a test for the empty case."; exit 0
fi
exit 1
