# external-agent

**A subcontractor skill for Claude Code.** Claude plans the work and delegates simple
to moderately difficult tasks to external coding agents:

- **OpenAI Codex CLI** (default model: `gpt-6.1-sol`)
- **Google Antigravity CLI** (`agy`, Gemini models)

The agent's work is verified automatically and independently reviewed. Claude steps
in only when a problem arises, leaving its tokens for difficult work such as design,
complex debugging, and decisions.

> Inspired by Superpowers' `subagent-driven-development` approach. Here, the
> sub-agents are separate CLIs rather than Claude instances.

---

## How it works

Claude writes a self-contained brief for each task and dispatches it with one command:

```
Claude ──brief──▶ agent_run.sh delegate
                    │
                    ├─ 0. quota      : reads Codex's latest recorded usage (skips Codex at 90% or above)
                    ├─ 1. implement  : Codex / Antigravity writes code (cannot commit)
                    ├─ 2. verify     : the SCRIPT runs the test command (the agent's "passed" claim is not enough)
                    ├─ 3. review     : a fresh, read-only session reviews against the brief
                    │                 (optionally from the other model family)
                    ├─ 4. fix        : sends critical/important findings back to the same session (up to 2 rounds)
                    │                 (if one agent runs out of quota, the other takes over its role)
                    └─ FINAL DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED | NEEDS_ATTENTION | LIMITED | FAILED
Claude ◀── one-line status + changed files + unresolved concerns
```

When the result is `DONE`, Claude moves to the next task without reading the change.
At the end, it runs all tests once and requests one review of the entire change.

### When a quota runs out

If an agent reaches its usage limit, the other agent takes over:

- **Before starting:** Codex writes its account quota to session files (5-hour and
  weekly windows). The script reads the latest record and shows it on the first line:
  `usage: codex 5h=40% week=12%`. If either window reaches 90%, Codex is skipped.
- **During a task:** If a step fails with an error such as "usage limit" or
  `RESOURCE_EXHAUSTED`, it is marked `LIMITED` and that agent is not used for the
  rest of the run.
  - *Implementation:* the other agent starts over and is told that partial changes
    may already be in the working tree.
  - *Fix round:* the other agent receives both the brief and the fix list.
  - *Review:* the other agent reviews. If a review from a different model family was
    requested but the fallback uses the same family, the `concerns:` line says so.
- **If both run out:** the result is `FINAL LIMITED`; the `limits:` line shows when
  each quota resets. If this happens during review, review is skipped and the result
  is `DONE_WITH_CONCERNS`.

When falling back to Antigravity, the script uses `EXTERNAL_AGENT_AGY_MODEL` if set,
or `gemini-4-argon-medium` otherwise. The `fallback:` line identifies the handoff;
Claude also mentions it in its report. Use `--no-fallback` to insist on one agent.

## Test results

The same three scenarios were used: a two-task Python plan, a JavaScript parser with
many edge cases, and a read-only bug investigation. Hidden tests, unseen by the
agents, were used for evaluation. Claude Opus 5.5 was the controller in every case.

| Configuration | Success | Agent time (plan / parser / investigation) | Notes |
|---|---|---|---|
| Without the skill, Claude + Codex | 93% | – | Two real bugs remained (fractional exactly-full container, NaN) |
| **Skill + Codex (gpt-6.1-sol)** | **100%** | 131 s / – / 74 s | Independent review caught real bugs |
| **Skill + Antigravity (Gemini 4 Argon)** | **100%** | 204 s / 149 s / 83 s | Similar to Codex in speed, with far fewer tokens |
| Skill + Antigravity (Gemini 3.8 Flash) | 100% | 373 s / 605 s / 170 s | Correct, but 2–4 times slower and used more tokens |

The Codex run for the parser scenario used a different mode, so its time is not
comparable and is shown as “–”.

Claude's token usage was about 75–98k per run regardless of the subcontractor;
roughly 60k of that was the fixed overhead of each Claude session.

---

## Requirements

| | macOS / Linux | Windows |
|---|---|---|
| Claude Code | ✓ | ✓ |
| bash | Included with the system (macOS bash 3.2 is sufficient) | **Git for Windows** (Git Bash); Claude Code uses it for its Bash tool |
| Python 3.8+ | `python3` | `python` (the script tries both and skips the Microsoft Store stub) |
| git | ✓ | ✓ (included with Git for Windows) |
| At least one subcontractor | `codex` and/or `agy`, signed in | Same |

- **Codex CLI:** run `brew install --cask codex` or `npm i -g @openai/codex`, then
  `codex login`.
- **Antigravity CLI:** included with the Antigravity app (`agy`). Run `agy update`
  to update it.

## Installation

### macOS / Linux

```bash
git clone https://github.com/cemalguvenn/external-agent.git
cd external-agent
./install.sh          # copies to ~/.claude/skills/external-agent
./install.sh --link   # or creates a symlink, updated with git pull
```

### Windows (PowerShell)

```powershell
git clone https://github.com/cemalguvenn/external-agent.git
cd external-agent
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The command installs to `%USERPROFILE%\.claude\skills\external-agent`. It warns if
Git Bash or Python is missing.

### Manual installation

Copy the `external-agent/` directory to `~/.claude/skills/`, then restart Claude Code.

## Usage

Ask in natural language; the skill activates automatically:

- "Have Codex do the tasks in plan.md, check each one, and do not commit."
- "Have Antigravity write the tests and Codex review them."
- "Ask Codex to investigate this bug without changing the code."
- "Give the routine work to external agents and focus on the architecture."
- "Have Gemini 4 Argon write parseDimensions and check it thoroughly."

**Antigravity model:** the skill does not hard-code a model. When Antigravity is
needed for the first time, it lists available models (`agy models`) and asks you to
choose, showing Gemini models first. Set `EXTERNAL_AGENT_AGY_MODEL` for a persistent
default.

### Settings (environment variables)

| Variable | Default | Description |
|---|---|---|
| `EXTERNAL_AGENT_MODEL` | `gpt-6.1-sol` | Codex model |
| `EXTERNAL_AGENT_AGY_MODEL` | (none; asks the user) | Antigravity model, e.g. `gemini-4-argon-medium`. Also used for fallback from Codex; if unset, fallback uses `gemini-4-argon-medium` |
| `EXTERNAL_AGENT_CODEX_MAX_PCT` | `90` | Skip Codex when its 5-hour or weekly usage reaches this percentage |
| `EXTERNAL_AGENT_RUNS` | `$TMPDIR/external-agent` | Root directory for run logs |
| `EXTERNAL_AGENT_SNAP_ROOT` | `~/.cache/external-agent` | Temporary project copies for Antigravity |

### Using the script directly

```bash
S=~/.claude/skills/external-agent/scripts/agent_run.sh
$S models --agent agy
$S delegate --agent agy --model gemini-4-argon-medium --review-agent codex \
   --cd ~/project --brief task.md --verify "npm test" --name task-1
$S delegate --agent codex --sandbox read-only --cd ~/project --brief question.md   # investigation only
$S delegate --agent codex --no-fallback --cd ~/project --brief task.md             # do not switch agents if quota runs out
```

## Safety and boundaries

- Subcontractors **do not commit**. The Codex brief forbids it and the script warns
  if Codex does commit; Antigravity's sandbox makes `.git` read-only. Claude stages
  accepted work, or commits it if you requested that.
- Codex runs in a `workspace-write` sandbox with network access disabled (enable it
  with `--network`).
- Antigravity's headless mode has no reliable read-only mode. Reviews and
  investigations therefore run in a **temporary copy** of the project; the real
  project is untouched and the copy is deleted afterward.
- Every instruction sent to Antigravity ends with the full schema and a scope rule
  forbidding access outside the project, to environment variables, or to other
  tools' data. Without this rule, Gemini Flash was observed exploring outside the
  project.
- For sensitive work (security, payments, data migration, public APIs), the skill
  switches to **manual review mode**: Claude reads and tests the changes itself.

### Known limitations

- **macOS:** Antigravity cannot work on projects under `~/Library/Application Support`
  because its sandbox blocks that location.
- **Antigravity trusted workspaces:** the project must be under a directory in
  Antigravity's `trustedWorkspaces` list (the home directory is trusted by default).
- **Antigravity quota cannot be checked in advance:** `agy` does not write usage
  information anywhere, so exhaustion is only detected when a step fails. A real
  quota error has not yet been observed; if exhaustion produces `FAILED` instead of
  `LIMITED`, add the error text to the script's `limit-check` patterns.
- **Windows:** Codex, Antigravity, mixed, and read-only pipelines were tested on
  Windows 11 25H2 (Git Bash, codex-cli 0.163, agy 1.4.6). Also:
  - Antigravity's terminal sandbox requires Windows 11 24H2.
  - A default Git for Windows installation adds only `Git\cmd` to PATH;
    `install.ps1` finds Git Bash beside `git.exe`, so `bash` need not be on the
    PowerShell PATH.
  - Use `python`, not `python3`, in verification commands (python.org installations
    do not include `python3`).
  - If Codex's Windows sandbox causes problems, use WSL.

## Troubleshooting

| Symptom | Solution |
|---|---|
| Codex exits with code 137 and no output | Claude Code's Bash sandbox is stopping Codex. The skill already runs its commands without that sandbox; disable it if running commands manually. |
| `codex: command not found` / broken symlink | `brew reinstall --cask codex` |
| `agy needs a model` | Choose one of the listed models |
| `jetski: no output produced … permission` | Call agy through the script instead of directly |
| Antigravity runs very slowly | Keep the project and temporary copy under the home directory |
| `stage … LIMITED`, `fallback:` line | One agent ran out of quota and the other took over. Codex is skipped from the outset when its quota reaches 90% (`EXTERNAL_AGENT_CODEX_MAX_PCT`). Use `--no-fallback` to insist on one agent. |
| `FINAL LIMITED` | Both agents ran out of quota; the `limits:` line shows when they reset |

See `external-agent/references/codex-cli.md` and `antigravity-cli.md` for details.

## Directory structure

```
external-agent/                 ← skill (install under ~/.claude/skills/)
├── SKILL.md                    ← instructions read by Claude
├── scripts/
│   ├── agent_run.sh            ← delegate / task / resume / review / models
│   ├── implementer.schema.json ← agent report schema
│   └── review.schema.json      ← review findings schema
├── references/                 ← brief templates, CLI notes, manual review mode
└── evals/                      ← 3 test scenarios (including hidden tests)
install.sh / install.ps1
```

You can rerun the evaluation scenarios with `claude plugin eval` (Claude Code
v2.1.269 or later). These are real, paid model runs.

## License

MIT. See `LICENSE` for details.
