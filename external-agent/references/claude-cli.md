# Claude Code CLI (`claude`) notes

Used as the `--agent claude` backend (primarily when **Antigravity / Neon** is the host
controller and delegates co-lead work, standard reviews, or economical Sonnet tasks to
Claude, or as a 3rd fallback). Never use `agy`'s bundled Claude models — always call
`claude` directly so Anthropic quota and Google quota stay separate.

## How the script drives it

| Step | Invocation (prompt passed via stdin to `claude -p`) |
|---|---|
| Implement / fix | `env -u ANTHROPIC_BASE_URL -u CLAUDECODE ... claude -p --model M --effort E --output-format json --permission-mode bypassPermissions --disable-slash-commands --json-schema '<compact-json>' < prompt.md` |
| Resume | same, plus `--resume <session_id>` |
| Review | same flags with `review.schema.json` and `--no-session-persistence`, run **in a disposable copy** with the diff pasted into the prompt |
| Read-only investigation | implement flags, run **in a disposable copy** |

- **Model aliases:** `opus` (default, resolves to the latest Opus on the account) and
  `sonnet` (fast economical helper). Full model IDs such as `claude-opus-5-5` or
  `claude-sonnet-5-5` also work.
- **Effort levels:** `claude --effort` supports `low`, `medium`, `high`, `max`. If the
  caller passes `--effort xhigh`, the script maps it to `max`.
- **`--disable-slash-commands`:** prevents a child `claude -p` from loading or recursively
  triggering the `external-agent` skill installed in `~/.claude/skills/`.
- **Env stripping:** `ANTHROPIC_BASE_URL`, `CLAUDECODE`, `CLAUDE_CODE_*`, and
  `CLAUDE_AGENT_*` are stripped before spawning `claude -p` so a child session uses its own
  authentication cleanly even if invoked from a Claude Code environment.
- **`--json-schema`:** `claude` expects an inline JSON string (not a file path); the
  script compacts `implementer.schema.json` / `review.schema.json` automatically.
- **Structured output & usage:** `--output-format json` returns one object containing
  `session_id`, `structured_output`, `result`, `is_error`, and `usage` (`input_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`).
- **Read-only isolation:** reviews and read-only investigations run in a disposable copy
  under `~/.cache/external-agent/external-agent-snap.XXXXXX` (`.git`, `node_modules`,
  etc. excluded) so Claude can run tests or reproducers safely without modifying the real
  working tree. The copy is removed when the run ends or is stopped; copies left by
  crashed runs are pruned automatically (see `antigravity-cli.md`).
- **Quota:** `claude` does not expose pre-run quota percentages to the script. If a run
  fails with a usage/rate limit error (`usage limit`, `hit your limit`, `rate limit`,
  `429`, `overloaded`), `limit-check` marks it `LIMITED` and `switch_role` moves the role
  to another available external agent.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `claude: command not found` | Claude Code CLI not installed or not on PATH | Install Claude Code (`claude install` / `npm i -g @anthropic-ai/claude-code`) and run `claude auth` |
| Auth / login errors inside child run | Session expired or inherited proxy env vars | Run `claude` interactively to re-authenticate; always call through `agent_run.sh` (which strips `CLAUDECODE` / `CLAUDE_CODE_*`) |
| `operation not permitted: claude` | Host sandbox blocked executing `claude` | Run `agent_run.sh` with the host sandbox disabled (`BypassSandbox: true` in Antigravity) |
| `stage … LIMITED claude: usage limit` | Claude subscription / rate limit hit | Automatic: another external agent takes over (or `FINAL LIMITED` if none left) |
