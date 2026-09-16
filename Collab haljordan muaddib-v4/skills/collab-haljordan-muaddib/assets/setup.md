# One-time setup so Claude Code can call Codex

1. Codex CLI installed and logged in: `npm install -g @openai/codex`, then `codex login` (ChatGPT plan or API key). Check: `codex login status`, `codex doctor`.
2. Official bridge (recommended, inside a Claude Code session):
   ```
   /plugin marketplace add openai/codex-plugin-cc
   /plugin install codex@openai-codex
   /reload-plugins
   /codex:setup
   ```
   This exposes `/codex:review`, `/codex:adversarial-review`, `/codex:rescue` (delegation through the `codex:codex-rescue` subagent), `/codex:transfer`, `/codex:status|result|cancel`. Leave the review gate off (`/codex:setup --enable-review-gate` can loop and drain both quotas).
3. Shared context: `AGENTS.md` at the repo root is the source of truth (build/test commands, layout, conventions, what not to touch). `CLAUDE.md` contains the line `@AGENTS.md` plus Claude-only notes.
4. Codex defaults for this repo in `.codex/config.toml` (trusted project) or `~/.codex/config.toml`:
   ```toml
   model_reasoning_effort = "high"
   approval_policy = "on-request"
   sandbox_mode = "workspace-write"
   ```
   Keep `network_access` off under `[sandbox_workspace_write]` unless a task needs it.
5. Optional, so the skill can read Claude's own quota on demand: point `statusLine.command` in `~/.claude/settings.json` to `<skill-dir>/scripts/claude_statusline_capture.sh`.
6. Optional fine-grained path: copy `assets/claude-agent-codex-delegate.md` to `.claude/agents/codex-delegate.md` and `assets/claude-command-delegate.md` to `.claude/commands/delegate-codex.md`; edit `<skill-dir>` in the agent file to the absolute skill path.
7. Verify the wrappers once on a throwaway branch: `scripts/codex_delegate.sh --repo . --task "print hello in README" --sandbox read-only` should produce a last message and change no files.
