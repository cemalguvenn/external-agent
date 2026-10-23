# Codex CLI notes (verified against codex-cli 0.163.0)

## Commands the script wraps

`delegate` chains these: task → `bash -c "$VERIFY"` in the repo → briefed review
(`--uncommitted`, files from the report) → `resume` with a generated fix brief → loop
(`--max-fix-rounds`, default 2). Stage dirs `01-implement/`, `02-verify/`, `03-review/`,
`04-fix-1/`, … and `summary.txt` sit in the run dir. `--no-review` skips the review;
`--sandbox read-only` skips verify and review.

| Need | Command |
|---|---|
| New task | `codex exec -m M -c model_reasoning_effort="E" -s workspace-write -C DIR --skip-git-repo-check --output-schema S -o report.json --json - < brief.md` |
| Continue same thread | `cd DIR && codex exec resume THREAD_ID -m M --skip-git-repo-check --output-schema S -o report.json --json - < fix.md` |
| Briefed review (default) | `codex exec -s read-only -C DIR --output-schema review.schema.json -o review.json --json - < review-prompt.md` |
| Built-in review | `cd DIR && codex exec review --uncommitted \| --base BR \| --commit SHA -m M -o review.md` |

- `codex exec review` rejects a custom `[PROMPT]` together with any target flag
  ("the argument '--uncommitted' cannot be used with '[PROMPT]'"). That's why briefed
  reviews go through a plain read-only `codex exec` session instead.

- `--json` prints JSONL events. `thread.started` carries `thread_id` (needed for resume);
  `turn.completed` carries token usage; `item.completed` items have types
  `agent_message`, `command_execution`, `file_change`, `error`.
- `--output-schema` enforces the final message shape. OpenAI structured output requires
  every property to be listed in `required` and `additionalProperties: false`.
- `resume` and `review` have **no `-C`** — run them from the project directory.
- `resume` without `--skip-git-repo-check` fails outside a trusted git dir with
  "Not inside a trusted directory".
- Sandbox modes: `read-only`, `workspace-write` (default here), `danger-full-access`.
  `workspace-write` **can** write `.git` (Codex can commit) — the brief forbids it and
  the script warns if HEAD moved.
- Network is off in `workspace-write`; `--network` adds
  `-c sandbox_workspace_write.network_access=true` (needed for `cargo build` fetching
  crates, `npm install`, `pip install`). Prefer installing deps yourself first.
- Never use `--dangerously-bypass-approvals-and-sandbox`.
- Models and effort levels available to the account are cached in
  `~/.codex/models_cache.json` (`slug`, `supported_reasoning_levels`).
- An `item.completed` of type `error` about deprecated config keys (e.g.
  `[features].codex_hooks`) is a warning from the user's config, not a task failure.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Exit 137, no output at all | Claude Code's Bash sandbox killed Codex | Re-run with the sandbox disabled |
| `command not found: codex` / broken symlink in `/opt/homebrew/bin/codex` | Binary removed (cleanup tools such as Mole can do this) | Ask the user to run `brew reinstall --cask codex` |
| `status=NO_REPORT` | Codex crashed, hit a limit, or was interrupted | Read `stderr.log` and the tail of `events.jsonl` in the run dir |
| Auth / 401 / "log in" errors | Codex session expired | User runs `codex login` themselves |
| Rate limit / quota errors | ChatGPT plan limits | Wait, lower effort, or do the task yourself; tell the user |
| Build tool can't download | Sandbox has no network | `--network`, or install deps yourself before dispatch |
| Codex edits files outside scope | Brief scope too loose | Revert those files, resume with an explicit "only touch X" |

## Cost intuition

Each Codex turn re-reads its system prompt plus the user's `~/.codex/AGENTS.md` and
installed skills: expect ~90–150k input tokens per turn even for tiny tasks (mostly
cached). A task that takes you under ~2 minutes to do directly is cheaper to do yourself.
