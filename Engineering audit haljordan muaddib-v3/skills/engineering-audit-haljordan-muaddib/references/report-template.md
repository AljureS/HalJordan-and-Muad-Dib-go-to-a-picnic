# Report template

Use this section order. Omit a module section only when that module was not in scope, and say so in the coverage summary. Keep the executive assessment under 250 words and give the 12 most important findings in full; everything else goes in Appendix A.

```markdown
# Engineering audit — <repository> — <YYYY-MM-DD> — by <agent>

## Executive assessment
Overall health in a few sentences, the three things that matter most, and what to protect. ≤ 250 words.

## Architecture map
Purpose · entry points · data flow · dependencies and integrations · critical workflows (traced end to end).
Mark each behaviour as implemented / partial / planned / obsolete, with the evidence that decided it.

## Prioritized findings
### Confirmed defects
### Unverified risks
### Design improvements

Finding format (repeat per finding):
**F-01 · <title>** — Severity: Critical|High|Medium|Low · Confidence: High|Medium|Low
- Where: `path/to/file.ts:123` or `path/to/file.ts:120-126` (`symbolName` or a ≤3-line verbatim excerpt, right after the citation so the checker can verify it)
- Failure scenario: what has to happen for this to bite
- Impact: who or what is affected, and how badly
- Fix: the practical change
- Tradeoffs: cost of fixing, migration effort, and when keeping the current approach makes sense

## Strengths to retain
Decisions and patterns worth preserving, with the reason each one is sound.

## Skills & agents assessment   ← module
Per skill / subagent / command / hook / instructions file: keep | clarify | consolidate | adapt — reason — verified or "unverified — assumption".

## Impact-versus-effort roadmap
Now (high impact, low effort) · Next · Later · Not worth it (and why).

## Collaboration playbook   ← module
Roles · task assignment · implementation/review rotation · independent verification · shared context (source-of-truth file) · decision records · handoff format · branch/worktree rules.

## Next five actions
1. Action → the engineering lesson behind it
(…five in total)

## Coverage summary
- Inspected (read fully) · Sampled (partially read) · Unreviewed
- Checks run: command → result → limitation
- Unresolved questions

## Appendix A — Findings table
| ID | Severity | Confidence | Type | File:line | One-line fix | Status |
|----|----------|------------|------|-----------|--------------|--------|
(Type = defect | risk | improvement. Status = open unless the owner says otherwise.)

## Appendix B — Questions for the owner and other agents
Things only the owner can answer, and open threads to hand to the other agent(s) working on the repository.
```
