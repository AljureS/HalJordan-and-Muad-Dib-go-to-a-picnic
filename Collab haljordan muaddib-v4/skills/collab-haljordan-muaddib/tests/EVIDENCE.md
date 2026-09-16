# Test evidence — 2026-09-16T19:33Z, Linux container, python3 3.12.3, bash 

```
PASS  real example: 7d role derived from 10080 min, not from 'primary'
PASS  real example: remaining 82
PASS  real example: secondary null -> unavailable, not zero
PASS  real example: plan and bucket carried
PASS  real example: verdict ok_with_unknown, eligible
PASS  two buckets: byLimitId used, legacy not double counted (2 records)
PASS  weekly 100% blocks bucket codex despite 5h at 40%
PASS  task on the spark bucket: that bucket eligible, codex bucket reported but not decisive
PASS  null usedPercent -> unavailable; 'n/a' -> unknown; never 0
PASS  null percentages -> verdict unknown, not eligible
PASS  claude: 5h remaining 76.5 and 7d remaining 58.8
PASS  claude: session tokens and cost recorded as separate dimensions
PASS  claude: verdict ok
PASS  claude without rate_limits -> unknown, not eligible
PASS  stale reading -> freshness stale and verdict unknown
PASS  account switch: only 'personal' records are judged
PASS  manual: weekly 10% left <= reserve -> blocked
PASS  both eligible: no ranking by percentage
PASS  reader: exit 0 and fixture returned through JSON-RPC (noise ignored)
PASS  reader: never sends a forbidden method (fake server would exit 9)
PASS  reader: missing binary -> exit 2
PASS  reader: unresponsive server -> exit 3 within timeout
PASS  capture: cache file written with observed_at wrapper
PASS  capture -> normalize reads the wrapper's observed_at
PASS  overlap: shared.ts detected, exit 1
PASS  overlap: disjoint sets -> exit 0
PASS  delegate: exit 0, reports the changed file and the last message
PASS  delegate: codex exec called with workspace-write, model and effort
PASS  delegate: never uses --full-auto or danger-full-access
PASS  delegate: record written, edits left uncommitted
PASS  delegate: refuses a dirty tree without --allow-dirty (exit 3)
PASS  delegate: --resume passes 'resume --last'
PASS  delegate: danger-full-access sandbox is refused (exit 2)
PASS  delegate: propagates codex's non-zero exit and records it
PASS  delegate: --task-file content is passed as the prompt
PASS  review: codex review --base main with focus, output captured to .collab/reviews
PASS  review: usage error without a target (exit 2)
----
passed 37, failed 0
```

Not covered here: a live `codex` CLI (no binary or network in this container) and a live Claude Code status line. codex_usage_read.py was exercised against tests/fake_app_server.py (three-method allow-list enforced); codex_delegate.sh and codex_review.sh against tests/fake_codex.sh (argv, exit codes, output capture). Verify once on your machine: `codex exec --help` and `codex review --help` for the flags the wrappers pass.
