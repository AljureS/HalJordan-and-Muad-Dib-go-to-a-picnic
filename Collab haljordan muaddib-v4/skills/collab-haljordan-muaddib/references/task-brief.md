# Task brief for a delegated task

Delegation fails on vague briefs, not on model quality. Write the brief before calling Codex, save it (e.g. `.collab/briefs/<slug>.md`) and pass it with `--task-file`.

```text
Objective (one sentence, observable result):
Acceptance criteria (how the owner will check it — commands, expected outputs):
Files/directories you own for this task (edit nothing else):
Context to read first (paths, AGENTS.md sections, existing tests):
Constraints: no new dependencies unless listed; keep public interfaces; follow AGENTS.md conventions
Do not: run anything under scripts/, touch .env*, migrations, CI, or credentials; do not commit
Tests to run before finishing (exact commands) and what "green" means:
Report back: files changed, commands run with results, open questions, anything you skipped
```

Keep one brief per task and one task per Codex run; a run that must "also" do three other things loses the ability to be verified.
