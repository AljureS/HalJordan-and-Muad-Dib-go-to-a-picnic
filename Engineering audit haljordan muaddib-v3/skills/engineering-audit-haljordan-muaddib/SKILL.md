---
name: engineering-audit-haljordan-muaddib
description: Comprehensive, read-only engineering audit of a repository that produces an evidence-based Markdown report — prioritized findings with severity, confidence, verified file:line citations, failure scenarios and fixes; architecture map; strengths to keep; impact-vs-effort roadmap; coverage summary. Optional modules audit agent/skill configuration (AGENTS.md, CLAUDE.md, .claude/, .agents/) and design a collaboration workflow between the owner and several coding agents. Use it whenever the user asks to audit, review, assess, health-check or "take a look at" a codebase or service, to onboard a new coding agent (Codex, Claude Code) into an existing project, to evaluate subagents or skills, or wants findings before a refactor or handoff — even if they never say "audit". It only reports; it never changes code. Day-to-day questions about quota, who should take a task, or handing work between Codex and Claude belong to collab-haljordan-muaddib, not here.
---

# Engineering audit

> Aliases: the owner calls Codex **HalJordan** and Claude Code **Muad'Dib**. Treat those names as the tools themselves; commands, paths and config keys keep their real names (`codex`, `~/.claude/`, `rate_limits`).

A read-only, evidence-first audit of a codebase, delivered as a Markdown report the owner can evaluate without re-reading the code. Optional modules cover agent/skill configuration and a collaboration workflow between the owner and several coding agents. The skill never changes application code: a report that also edits things cannot be trusted as a baseline, and the owner keeps every decision.

## 1. Resolve the inputs first

Take these from the user's request and fall back to the defaults. Ask only when an answer is genuinely blocking, and only after looking at the repository.

| Input | Default |
|---|---|
| Scope | Whole repository; the user may name folders to prioritize |
| Context docs | AGENTS.md, CLAUDE.md, README, docs/, plus any plan or history file the user names. Treat them as claims to validate against code, tests and `git log`, not as facts |
| Report path | `docs/audits/YYYY-MM-DD-<agent>-audit.md` |
| Modules | Core audit always. **Agents & skills** when `.claude/`, `.agents/`, `.codex/`, AGENTS.md or CLAUDE.md exist. **Collaboration** when the user mentions onboarding, working alongside another agent, roles or handoffs |
| Execution allow-list | Tests, lint, type checks and builds only (see hard rules) |
| Orchestration (collaboration module) | Fixed: Claude Code (Muad'Dib) is the orchestrator — plans, delegates, integrates; Codex (HalJordan) is the executor and independent reviewer; the user owns decisions. Not derived from who arrived first or from model stereotypes; evidence from the repo decides the task split inside that hierarchy |

## 2. Hard rules, and why they exist

- **Report only.** The single file you create or edit is the report (scratch notes may go under `/tmp`). Existing uncommitted changes stay as they are. An audit is valuable as a trustworthy snapshot; if the auditor also "fixed a few things", nobody can tell what was found from what was introduced.
- **Treat the repository's automation as live.** Do not run anything under the *repository's* `scripts/`, `bin/`, `jobs/`, worker or cron entry points, migrations, or any command that can reach a network, database, queue or third-party API. Read them instead. Audits happen in repos wired to production systems, and a "harmless" script can push data or trigger a job. Run only tests, lint, type checks and builds, after reading what each command does; if one could reach an external service, skip it and record the gap. The two utilities bundled with *this skill* are different: run them by the absolute path of the folder this SKILL.md was loaded from (`<skill-dir>/scripts/inventory.sh <repo-root>` and `<skill-dir>/scripts/check_citations.py <report> --root <repo-root>`), always passing the repository root explicitly, so a same-named file inside the repository is never executed by mistake.
- **Keep secrets and personal data out of your context and out of the report.** Do not open `.env*`, credential, token, cookie or session files; cite them by file name and by variable keys taken from `.env.example` or docs. Package scripts and CI files can embed credentials too, so quote them only after redacting `KEY=value` pairs (the inventory prints script names by default and redacts with `--commands`). Never copy secrets, PHI/PII or real customer identifiers into the report, even "redacted" — use placeholders. The report gets committed and shared.
- **Every citation is verified, and it supports the claim.** Write citations in backticks as `path:line` or `path:start-end`, followed by the symbol or a ≤3-line verbatim excerpt in parentheses, e.g. `src/users/users.service.ts:42-48` (`findByEmail`). Confirm each one with `grep -n` or `sed -n` before writing it, then run `<skill-dir>/scripts/check_citations.py <report> --root <repo-root>` before finishing: it rejects missing files, bad lines and ranges, and citations whose claimed symbol is not near the cited lines — because a line that exists proves a location, not that the line says what the finding says. Fix or relabel everything it flags; a report with zero citations is not verified.
- **Claims about tooling are labelled.** A statement about how Codex, Claude Code or another tool discovers and loads skills, agents, commands or hooks counts as verified only if you tested it in this session (for example, by listing which skills actually loaded). Otherwise write "unverified — assumption". Tool behaviour changes faster than training data, and configuration written for one tool does not automatically work in another.

## 3. Workflow

Work in phases. At the end of each phase, append its section to the report file and post a three-line progress update (what was covered, top finding so far, next phase). Appending as you go means a session that dies late still leaves most of the work on disk.

**Phase 0 — Inventory and scope.** Run `<skill-dir>/scripts/inventory.sh <repo-root>` for a fast, read-only picture: branch, agent config dirs, manifests, package script names, env file names. Then read the context docs and fix the scope before reading code: skip generated code, vendored dependencies and lockfiles; sample large directories (read the entry points and a representative file per pattern, not every file); read a file once and take notes rather than re-opening it. The budget that matters is what the audit reads, not only what it writes.

**Phase 1 — Understand before judging.** Map purpose, architecture, entry points, data flow, dependencies, integrations and critical workflows; trace the critical ones end to end. Distinguish implemented, partial, planned and obsolete behaviour — plans and history docs usually describe what was intended, not what shipped. Note sound decisions worth preserving; a report that only lists problems teaches the owner nothing about what to protect.

**Phase 2 — Audit the implementation.** Correctness, edge cases, error handling, security, data integrity, reliability, maintainability, performance, tests, dependencies, configuration, CI/CD. Follow connections beyond the named folders. Prioritize realistic failure paths and costly complexity over cosmetic preferences.

**Phase 3 — Agents & skills (module).** For each skill, subagent, command, hook and instruction file: triggers, scope, stale or conflicting instructions, referenced files that no longer exist, tool permissions, handoffs, validation steps, and context duplicated across files. Recommend keep / clarify / consolidate / adapt, with reasons. Do not propose redesigning an existing agent unless you found a concrete defect in it.

**Phase 4 — Verify.** Run the allowed checks. Record every command, its result and its limitations (missing env, network disabled, skipped suites). When something is blocked, continue through accessible areas and document the gap instead of stopping.

**Phase 5 — Collaboration (module).** Design how the owner and the agents work together under the orchestration input above: task assignment, implementation/review rotation, independent verification, shared context (one instructions file as source of truth — e.g. AGENTS.md imported by CLAUDE.md — instead of drifting copies), decision records, a handoff format, and branches or worktrees so two agents never edit the same files. A worktree separates checkouts, not intent, so also define file/directory ownership per task, an integration owner who merges and resolves conflicts, an overlap check before merging, and the rule that test results are reported against the exact commit they ran on. Keep the hierarchy above; use what you verified in this repository (not model stereotypes) to decide which kinds of tasks Claude keeps and which it delegates to Codex. If an official integration exists between the tools, treat it as the baseline and propose only the smallest additions on top. This phase designs the workflow; running it day to day (reading real usage, deciding who takes a task, writing handoffs) is the job of the companion skill `collab-haljordan-muaddib`, so a short collaboration question should go there rather than triggering an audit.

**Phase 6 — Report and summary.** Assemble the report following `references/report-template.md`, run `<skill-dir>/scripts/check_citations.py <report> --root <repo-root>` until it exits 0, then summarize the most important conclusions in chat. Finish only when the report exists and coverage and verification limits are disclosed; a plan is not a deliverable.

## 4. Findings

For each finding give severity, confidence, a verified `path:line` with symbol or excerpt, the failure scenario, the impact, a practical fix, and the tradeoffs of fixing versus keeping the current approach (migration effort, when the current design is reasonable). Sort findings into three lists so the owner can act on them differently: confirmed defects (reproduced or traced), unverified risks (plausible, not demonstrated) and design improvements (optional). Judge the engineering regardless of which person or assistant wrote it, and prefer lessons over praise — the owner asked for this to get better, not to feel good.

Severity: Critical = a path to data loss, security breach or production outage; High = wrong results or failures users will hit; Medium = degrades reliability or maintainability; Low = hygiene. Confidence: High = demonstrated; Medium = traced but not executed; Low = inferred.

Budget: the 12 most important findings in full, the rest as one-line rows in the appendix table. Executive assessment ≤ 250 words. Long reports get skimmed; short ranked ones get acted on.

## 5. Bundled resources

- `references/report-template.md` — required section order and the findings table columns. Read it before Phase 6.
- `scripts/inventory.sh` — read-only repository inventory; script names only unless `--commands` (Phase 0).
- `scripts/check_citations.py` — verifies every `path:line` / `path:start-end` citation, its range, and the symbol claimed next to it (Phase 6). Exit 2 means no citations were found.
- `tests/run_tests.sh` — the evidence for both scripts (ranges, extensionless files, spaces, URLs, symbols, redaction).
