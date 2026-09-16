#!/usr/bin/env bash
# Test evidence for collab-haljordan-muaddib. Run from anywhere: tests/run_tests.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; S="$here/.."; F="$here/fixtures"
NOW="2026-09-16T18:20:00Z"   # fixed clock: fixtures' resetsAt are in Sept 2026
tmp=$(mktemp -d); pass=0; fail=0
ok()   { pass=$((pass+1)); echo "PASS  $1"; }
bad()  { fail=$((fail+1)); echo "FAIL  $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
py=python3
N="$py $S/scripts/usage_normalize.py"; D="$py $S/scripts/usage_decide.py"

# 1. Real Codex example: weekly window known (82% left), secondary unknown
$N --provider openai --account-alias rayo-codex --now "$NOW" "$F/codex_real_example.json" > "$tmp/real.json"
check "real example: 7d role derived from 10080 min, not from 'primary'" "grep -q '\"window_role\": \"7d\"' $tmp/real.json"
check "real example: remaining 82"                                       "grep -q '\"remaining_percent\": 82.0' $tmp/real.json"
check "real example: secondary null -> unavailable, not zero"            "$py -c \"import json;r=json.load(open('$tmp/real.json'))['records'][0];w=r['windows'][1];assert w['availability']=='unavailable' and w['used_percent'] is None\""
check "real example: plan and bucket carried"                            "grep -q '\"plan\": \"plus\"' $tmp/real.json && grep -q '\"bucket_id\": \"codex\"' $tmp/real.json"
$D --records "$tmp/real.json" --reserve 15 --now "$NOW" > "$tmp/real.dec" 2>/dev/null
check "real example: verdict ok_with_unknown, eligible"                  "grep -q '\"verdict\": \"ok_with_unknown\"' $tmp/real.dec && grep -q 'openai:rayo-codex' $tmp/real.dec"

# 2. Weekly exhausted blocks even though 5h has room; other bucket stays eligible only if the task targets it
$N --provider openai --account-alias rayo-codex --now "$NOW" "$F/codex_two_buckets_weekly_exhausted.json" > "$tmp/two.json"
check "two buckets: byLimitId used, legacy not double counted (2 records)" "$py -c \"import json;assert len(json.load(open('$tmp/two.json'))['records'])==2\""
$D --records "$tmp/two.json" --reserve 15 --now "$NOW" --bucket codex > "$tmp/two.dec" 2>/dev/null
check "weekly 100% blocks bucket codex despite 5h at 40%"                "$py -c \"import json;d=json.load(open('$tmp/two.dec'));v=[x for x in d['verdicts'] if x['bucket_id']=='codex'][0];assert v['verdict']=='blocked' and d['eligible_accounts']==[]\""
$D --records "$tmp/two.json" --reserve 15 --now "$NOW" --bucket codex_bengalfox > "$tmp/two2.dec" 2>/dev/null
check "task on the spark bucket: that bucket eligible, codex bucket reported but not decisive" "$py -c \"import json;d=json.load(open('$tmp/two2.dec'));assert d['eligible_accounts']==['openai:rayo-codex'] and any(x['bucket_id']=='codex' and not x['applicable_to_task'] for x in d['verdicts'])\""

# 3. Null / non-numeric percentages stay unknown
$N --provider openai --now "$NOW" "$F/codex_null_percent.json" > "$tmp/null.json"
check "null usedPercent -> unavailable; 'n/a' -> unknown; never 0"       "$py -c \"import json;w=json.load(open('$tmp/null.json'))['records'][0]['windows'];assert w[0]['availability']=='unavailable' and w[1]['availability']=='unknown' and all(x['used_percent'] is None for x in w)\""
$D --records "$tmp/null.json" --now "$NOW" > "$tmp/null.dec" 2>/dev/null
check "null percentages -> verdict unknown, not eligible"                "grep -q '\"verdict\": \"unknown\"' $tmp/null.dec && grep -q '\"eligible_accounts\": \[\]' $tmp/null.dec"

# 4. Claude statusline: both windows known; session tokens/cost kept separate from quota
$N --provider anthropic --account-alias rayo-claude --now "$NOW" "$F/claude_statusline_pro.json" > "$tmp/cl.json"
check "claude: 5h remaining 76.5 and 7d remaining 58.8"                   "grep -q '\"remaining_percent\": 76.5' $tmp/cl.json && grep -q '\"remaining_percent\": 58.8' $tmp/cl.json"
check "claude: session tokens and cost recorded as separate dimensions"   "grep -q 'not a quota' $tmp/cl.json && grep -q 'not a bill' $tmp/cl.json"
$D --records "$tmp/cl.json" --reserve 15 --now "$NOW" > "$tmp/cl.dec" 2>/dev/null
check "claude: verdict ok"                                                "grep -q '\"verdict\": \"ok\"' $tmp/cl.dec"

# 5. Claude without rate_limits -> unknown
$N --provider anthropic --now "$NOW" "$F/claude_statusline_no_limits.json" > "$tmp/cl0.json"
$D --records "$tmp/cl0.json" --now "$NOW" > "$tmp/cl0.dec" 2>/dev/null
check "claude without rate_limits -> unknown, not eligible"               "grep -q 'rate_limits absent' $tmp/cl0.json && grep -q '\"verdict\": \"unknown\"' $tmp/cl0.dec"

# 6. Stale reading (2 h old, max age 30 min) -> unknown
$N --provider anthropic --now "$NOW" --observed-at 2026-09-16T16:00:00Z "$F/claude_statusline_pro.json" > "$tmp/stale.json"
$D --records "$tmp/stale.json" --now "$NOW" --max-age-min 30 > "$tmp/stale.dec" 2>/dev/null
check "stale reading -> freshness stale and verdict unknown"              "grep -q '\"freshness\": \"stale\"' $tmp/stale.json && grep -q '\"verdict\": \"unknown\"' $tmp/stale.dec"

# 7. Account switch: ledger holds two aliases; deciding for one ignores the other
$N --provider openai --account-alias work --now "$NOW" --ledger "$tmp/ledger.jsonl" "$F/codex_two_buckets_weekly_exhausted.json" >/dev/null
$N --provider openai --account-alias personal --now "$NOW" --ledger "$tmp/ledger.jsonl" "$F/codex_real_example.json" >/dev/null
$D --ledger "$tmp/ledger.jsonl" --account-alias personal --now "$NOW" > "$tmp/sw.dec" 2>/dev/null
check "account switch: only 'personal' records are judged"                "$py -c \"import json;d=json.load(open('$tmp/sw.dec'));assert {v['account_alias'] for v in d['verdicts']}=={'personal'} and d['eligible_accounts']==['openai:personal']\""

# 8. Manual reading: 7d at 90% used blocks under reserve 15 although 5h has 40% left
$N --provider manual --account-alias rayo-claude --now "$NOW" "$F/manual_windows.json" > "$tmp/man.json"
$D --records "$tmp/man.json" --reserve 15 --now "$NOW" > "$tmp/man.dec" 2>/dev/null
check "manual: weekly 10% left <= reserve -> blocked"                     "grep -q '\"verdict\": \"blocked\"' $tmp/man.dec && grep -q 'manual reading' $tmp/man.json"

# 9. No cross-provider ranking: both eligible, output says choose by task fit
$D --records "$tmp/real.json" "$tmp/cl.json" --reserve 15 --now "$NOW" > "$tmp/both.dec" 2>/dev/null
check "both eligible: no ranking by percentage"                           "$py -c \"import json;d=json.load(open('$tmp/both.dec'));assert d['eligible_accounts']==['anthropic:rayo-claude','openai:rayo-codex'] and 'never by comparing percentages' in d['choose_by']\""

# 10. Reader end-to-end against a fake app-server; only allowed methods are sent
FAKE_FIXTURE="$F/codex_real_example.json" $py "$S/scripts/codex_usage_read.py" --codex-bin "$py $here/fake_app_server.py" --settle 0.05 > "$tmp/read.json" 2>"$tmp/read.err"; rc=$?
check "reader: exit 0 and fixture returned through JSON-RPC (noise ignored)" "[[ $rc -eq 0 ]] && grep -q '\"limitId\": \"codex\"' $tmp/read.json"
check "reader: never sends a forbidden method (fake server would exit 9)"     "! grep -q forbidden $tmp/read.err"
$py "$S/scripts/codex_usage_read.py" --codex-bin "/nonexistent/codex" >/dev/null 2>&1; rc=$?
check "reader: missing binary -> exit 2"                                       "[[ $rc -eq 2 ]]"
FAKE_FIXTURE="$F/codex_real_example.json" $py "$S/scripts/codex_usage_read.py" --codex-bin "$py -c 'import time;time.sleep(5)'" --timeout 1 >/dev/null 2>&1; rc=$?
check "reader: unresponsive server -> exit 3 within timeout"                    "[[ $rc -eq 3 ]]"

# 11. Statusline capture writes the cache without secrets and prints a line
COLLAB_DIR="$tmp/collab" bash "$S/scripts/claude_statusline_capture.sh" < "$F/claude_statusline_pro.json" > "$tmp/cap.out"
check "capture: cache file written with observed_at wrapper"               "grep -q '\"observed_at\"' $tmp/collab/claude-statusline-latest.json && grep -q 'seven_day' $tmp/collab/claude-statusline-latest.json"
$N --provider anthropic --now "$NOW" "$tmp/collab/claude-statusline-latest.json" > "$tmp/cap.json"
check "capture -> normalize reads the wrapper's observed_at"               "grep -q '\"observed_at\": \"$(date -u +%Y-%m-%d)' $tmp/cap.json"

# 12. Overlap check on a throwaway repo
r="$tmp/repo"; mkdir -p "$r" && cd "$r" && git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m base
printf 'a\n' > shared.ts; printf 'x\n' > only-a.ts; git add -A; git -c user.email=t@t -c user.name=t commit -qm base2
git checkout -qb feat-a; printf 'aa\n' > shared.ts; printf 'x2\n' > only-a.ts; git commit -qam a
git checkout -q master 2>/dev/null || git checkout -q main; git checkout -qb feat-b; printf 'bb\n' > shared.ts; git commit -qam b
base=$(git rev-parse --abbrev-ref HEAD >/dev/null; git branch --list master main | head -1 | tr -d ' *')
bash "$S/scripts/overlap_check.sh" "$base" feat-a feat-b > "$tmp/ov.out"; rc=$?
check "overlap: shared.ts detected, exit 1"                                "[[ $rc -eq 1 ]] && grep -q 'shared.ts' $tmp/ov.out"
git checkout -q feat-a; printf 'z\n' > only-a.ts
bash "$S/scripts/overlap_check.sh" "$base" feat-a "$base" > "$tmp/ov2.out"; rc=$?
check "overlap: disjoint sets -> exit 0"                                   "[[ $rc -eq 0 ]]"
cd "$here"


# 13. Delegation wrapper against a fake codex
d="$tmp/drepo"; mkdir -p "$d/src" && cd "$d" && git init -q && git config user.email t@t && git config user.name t
printf 'const a = 1;\n' > src/app.ts && git add -A && git commit -qm base
FAKE="$here/fake_codex.sh"
FAKE_CODEX_LOG="$tmp/argv.log" FAKE_CODEX_TOUCH=1 bash "$S/scripts/codex_delegate.sh" --repo "$d" --task "refactor app" --model gpt-5.3-codex --effort high --codex-bin "$FAKE" > "$tmp/del.out" 2>&1; rc=$?
check "delegate: exit 0, reports the changed file and the last message"   "[[ $rc -eq 0 ]] && grep -q 'src/app.ts' $tmp/del.out && grep -q 'Done: refactored' $tmp/del.out"
check "delegate: codex exec called with workspace-write, model and effort" "grep -qx 'exec' $tmp/argv.log && grep -qx -- '--sandbox' $tmp/argv.log && grep -qx 'workspace-write' $tmp/argv.log && grep -qx 'gpt-5.3-codex' $tmp/argv.log && grep -q 'model_reasoning_effort=\"high\"' $tmp/argv.log"
check "delegate: never uses --full-auto or danger-full-access"            "! grep -q 'full-auto' $tmp/argv.log && ! grep -q 'danger' $tmp/argv.log"
check "delegate: record written, edits left uncommitted"                  "ls $d/.collab/delegations/*-delegation.json >/dev/null && grep -q '\"committed\": false' $d/.collab/delegations/*-delegation.json && [[ -n \"\$(git -C $d status --short)\" ]]"
FAKE_CODEX_LOG="$tmp/argv2.log" bash "$S/scripts/codex_delegate.sh" --repo "$d" --task "continue" --codex-bin "$FAKE" > "$tmp/del2.out" 2>&1; rc=$?
check "delegate: refuses a dirty tree without --allow-dirty (exit 3)"       "[[ $rc -eq 3 ]] && grep -q 'uncommitted changes' $tmp/del2.out"
FAKE_CODEX_LOG="$tmp/argv3.log" bash "$S/scripts/codex_delegate.sh" --repo "$d" --task "continue" --resume --allow-dirty --codex-bin "$FAKE" > "$tmp/del3.out" 2>&1; rc=$?
check "delegate: --resume passes 'resume --last'"                          "[[ $rc -eq 0 ]] && grep -qx 'resume' $tmp/argv3.log && grep -qx -- '--last' $tmp/argv3.log"
bash "$S/scripts/codex_delegate.sh" --repo "$d" --task "x" --sandbox danger-full-access --allow-dirty --codex-bin "$FAKE" > "$tmp/del4.out" 2>&1; rc=$?
check "delegate: danger-full-access sandbox is refused (exit 2)"           "[[ $rc -eq 2 ]] && grep -q 'refusing sandbox' $tmp/del4.out"
FAKE_CODEX_LOG="$tmp/argv5.log" FAKE_CODEX_EXIT=7 bash "$S/scripts/codex_delegate.sh" --repo "$d" --task "x" --allow-dirty --codex-bin "$FAKE" > "$tmp/del5.out" 2>&1; rc=$?
check "delegate: propagates codex's non-zero exit and records it"          "[[ $rc -eq 7 ]] && grep -q 'exit code: 7' $tmp/del5.out"
printf 'x\n' > "$tmp/brief.md"
FAKE_CODEX_LOG="$tmp/argv6.log" bash "$S/scripts/codex_delegate.sh" --repo "$d" --task-file "$tmp/brief.md" --allow-dirty --codex-bin "$FAKE" >/dev/null 2>&1
check "delegate: --task-file content is passed as the prompt"              "grep -qx 'x' $tmp/argv6.log"

# 14. Review wrapper
FAKE_CODEX_LOG="$tmp/argv7.log" bash "$S/scripts/codex_review.sh" --repo "$d" --base main --focus "error handling" --codex-bin "$FAKE" > "$tmp/rev.out" 2>&1
check "review: codex review --base main with focus, output captured to .collab/reviews" "grep -qx 'review' $tmp/argv7.log && grep -qx -- '--base' $tmp/argv7.log && grep -qx 'error handling' $tmp/argv7.log && ls $d/.collab/reviews/*-review.md >/dev/null && grep -q 'no blocking issues' $tmp/rev.out"
bash "$S/scripts/codex_review.sh" --repo "$d" > "$tmp/rev2.out" 2>&1; rc=$?
check "review: usage error without a target (exit 2)"                      "[[ $rc -eq 2 ]]"
cd "$here"
echo "----"; echo "passed $pass, failed $fail"
rm -rf "$tmp"
[[ $fail -eq 0 ]]
