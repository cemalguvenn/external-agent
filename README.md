# external-agent

**English** · [Türkçe](README.tr.md)

**A subcontractor skill for Claude Code.** Claude plans the work and hands simple and
medium-difficulty tasks to external coding agents:

- **OpenAI Codex CLI** (default model `gpt-6.1-sol`)
- **Google Antigravity CLI** (`agy`, Gemini models)

The agent's work is verified automatically and goes through an independent review.
Claude steps in only when something goes wrong. That keeps Claude's tokens for the hard
parts (design, tricky debugging, decisions) while the subcontractors do the chores.

> Inspired by Superpowers' `subagent-driven-development` approach. The difference: the
> sub-agents are separate CLIs, not Claude.

---

## How it works

For each task Claude writes a self-contained brief and sends it with one command:

```
Claude ──brief──▶ agent_run.sh delegate
                    │
                    ├─ 0. quota     : reads Codex's last recorded usage (Codex is skipped at 90% or more)
                    ├─ 1. implement : Codex / Antigravity writes the code (it cannot commit)
                    ├─ 2. verify    : the SCRIPT runs the test command (the agent saying "passed" doesn't count)
                    ├─ 3. review    : a fresh, read-only session reviews the change against the brief
                    │                 (optionally from the other model family)
                    ├─ 4. fix       : critical/important findings go back to the same thread (up to 2 rounds)
                    │   (if an agent runs out of quota, the other agent takes over its role)
                    └─ FINAL DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED | NEEDS_ATTENTION | LIMITED | FAILED
Claude ◀── one status line + changed files + open notes
```

On `DONE` Claude doesn't read the change; it moves on to the next task. At the end it
runs the whole test suite once and has the whole change reviewed once.

### When an agent runs out of quota

If an agent hits its usage limit, the work doesn't stop halfway; the other agent takes
over its role:

- **Before starting:** Codex writes the account's quota (5-hour and weekly windows) into
  its session files. The script reads the newest one and shows it on the first line:
  `usage: codex 5h=40% week=12%`. If either window is at 90% or more, Codex is skipped
  from the start.
- **During the task:** a step that fails with an error such as "usage limit" or
  `RESOURCE_EXHAUSTED` is marked `LIMITED`, and that agent isn't used for the rest of
  the run.
  - *Implement:* the other agent starts over and is told the partial changes may
    already be in the working tree.
  - *Fix round:* the other agent gets the brief and the fix list together.
  - *Review:* the other agent reviews. If you asked for a cross-family review and it
    ended up same-family, the `concerns:` line says so.
- **If both are out:** the result is `FINAL LIMITED`, and the `limits:` line says who
  resets when. If it happened during review, the review is skipped and the result is
  `DONE_WITH_CONCERNS`.

A fallback to Antigravity with no model chosen uses `EXTERNAL_AGENT_AGY_MODEL`, else
`gemini-4-argon-medium`. Every takeover shows on a `fallback:` line, and Claude mentions
it in its report. To insist on one agent, pass `--no-fallback`.

## Test results

The same 3 scenarios were used: a two-task Python plan, an edge-case-heavy JS parser,
and a read-only bug investigation. Grading used hidden tests the agents never saw. The
controller was Claude Opus 5.5 throughout.

| Setup | Pass rate | Agent time (plan / parser / investigation) | Note |
|---|---|---|---|
| Without the skill, Claude + Codex | 93% | – | 2 real bugs left in the code (fractional exactly-full container, NaN) |
| **Skill + Codex (gpt-6.1-sol)** | **100%** | 131 s / – / 74 s | The independent review caught the real bugs |
| **Skill + Antigravity (Gemini 4 Argon)** | **100%** | 204 s / 149 s / 83 s | Time close to Codex, far fewer tokens |
| Skill + Antigravity (Gemini 3.8 Flash) | 100% | 373 s / 605 s / 170 s | Correct, but 2-4x slower and more tokens |

The parser scenario's Codex run used a different mode, so its time isn't comparable;
that's the "–" in the table.

On Claude's side, token use was about 75-98k per run whichever subcontractor was used.
About 60k of that is the fixed cost of any Claude session.

---

## Requirements

| | macOS / Linux | Windows |
|---|---|---|
| Claude Code | ✓ | ✓ |
| bash | built in (macOS's bash 3.2 is enough) | **Git for Windows** (Git Bash). Claude Code uses it for its Bash tool too |
| Python 3.8+ | `python3` | `python` (the script tries both and skips the Microsoft Store alias) |
| git | ✓ | ✓ (comes with Git for Windows) |
| At least one subcontractor | `codex` and/or `agy`, signed in | same |

- **Codex CLI:** `brew install --cask codex` or `npm i -g @openai/codex`, then
  `codex login`.
- **Antigravity CLI:** comes with the Antigravity app (`agy`). Update with `agy update`.

## Installation

### macOS / Linux

```bash
git clone https://github.com/cemalguvenn/external-agent.git
cd external-agent
./install.sh          # copies to ~/.claude/skills/external-agent
./install.sh --link   # or symlinks it, so `git pull` updates the skill
```

### Windows (PowerShell)

```powershell
git clone https://github.com/cemalguvenn/external-agent.git
powershell -ExecutionPolicy Bypass -File .\external-agent\install.ps1
```

This installs to `%USERPROFILE%\.claude\skills\external-agent` and warns if Git Bash or
Python is missing. To update, run the same command with `-Force` after `git pull`.

- The `-File` path is relative to the folder you run the command from. If you get
  `The argument '.\install.ps1' to the -File parameter does not exist`, give the
  script's full path: `powershell -ExecutionPolicy Bypass -File C:\...\external-agent\install.ps1`.
- A ZIP download from GitHub unpacks into `external-agent-main`.
- The Windows install leaves out `evals/`: Claude doesn't use it, and its deep paths can
  exceed Windows PowerShell 5.1's 260-character path limit.

### Manual installation

Copy the `external-agent/` folder into `~/.claude/skills/`. Restart Claude Code after
installing.

## Usage

Ask as you normally would, in any language; the skill kicks in on its own:

- "run the tasks in plan.md with codex, check each one, don't commit"
- "give writing the tests to antigravity, and have codex review"
- "have codex investigate the cause of this bug, but it must not change the code"
- "hand the chores to external agents, you focus on the architecture"
- "have gemini 4 argon write parseDimensions, and check it thoroughly"

**Antigravity model:** the skill doesn't hard-code a model. The first time Antigravity is
needed, it lists the available models (`agy models`) and lets you pick, Gemini models
first. For a standing default, set `EXTERNAL_AGENT_AGY_MODEL`.

### Settings (environment variables)

| Variable | Default | Description |
|---|---|---|
| `EXTERNAL_AGENT_MODEL` | `gpt-6.1-sol` | Codex model |
| `EXTERNAL_AGENT_AGY_MODEL` | (none, you're asked) | Antigravity model, e.g. `gemini-4-argon-medium`. Also used when a task falls back from Codex; if unset, `gemini-4-argon-medium` |
| `EXTERNAL_AGENT_CODEX_MAX_PCT` | `90` | Codex is skipped once its 5-hour or weekly usage reaches this percentage |
| `EXTERNAL_AGENT_RUNS` | `$TMPDIR/external-agent` | Root folder for run logs |
| `EXTERNAL_AGENT_SNAP_ROOT` | `~/.cache/external-agent` | Antigravity's temporary project copies |

### Using the script directly

```bash
S=~/.claude/skills/external-agent/scripts/agent_run.sh
$S models --agent agy
$S delegate --agent agy --model gemini-4-argon-medium --review-agent codex \
   --cd ~/project --brief task.md --verify "npm test" --name task-1
$S delegate --agent codex --sandbox read-only --cd ~/project --brief question.md   # investigation only
$S delegate --agent codex --no-fallback --cd ~/project --brief task.md            # never switch agents
```

## Safety and limits

- Subcontractors **never commit**. The brief forbids it for Codex and the script warns
  if it does; Antigravity's sandbox makes `.git` read-only. Claude stages accepted work,
  or commits it if you asked.
- Codex runs in its `workspace-write` sandbox with network off (`--network` turns it on).
- Antigravity's headless mode has no reliable read-only mode, so reviews and
  investigations run in a **temporary copy** of the project; the real project isn't
  touched, and the copy is deleted afterwards.
- Every prompt to Antigravity ends with the full schema and a scope rule: no looking
  outside the project folder, at environment variables or at other tools' data. Without
  it, Gemini Flash was seen wandering outside the project.
- For risky work (security, payments, data migrations, public APIs) the skill switches
  to **manual mode**: Claude reads and tests the changes itself.

### Known limitations

- **macOS:** Antigravity can't work on projects under `~/Library/Application Support`
  (its sandbox blocks it).
- **Antigravity trusted workspaces:** the project must be under a folder in
  Antigravity's `trustedWorkspaces` list (your home folder by default).
- **Antigravity's quota can't be seen in advance:** `agy` doesn't write its usage
  anywhere, so a limit only shows when a step fails. Its real quota error hasn't been
  seen yet; if Antigravity runs out and the result is `FAILED` instead of `LIMITED`,
  add the message's wording to the `limit-check` patterns in the script.
- **Windows:** tested on Windows 11 25H2 (Git Bash, codex-cli 0.163, agy 1.4.6) with the
  Codex, Antigravity, mixed and read-only pipelines. Also:
  - Antigravity's terminal sandbox needs Windows 11 24H2.
  - Git for Windows' default install adds only `Git\cmd` to PATH; `install.ps1` finds Git
    Bash next to `git.exe`, so no `bash` in PowerShell is fine.
  - Write `python`, not `python3`, in verify commands (a python.org install has no
    `python3`).
  - If Codex's Windows sandbox gives trouble, use it inside WSL.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Codex exit code 137, no output at all | Claude Code's Bash sandbox is stopping Codex. The skill already runs its commands with the sandbox off; if you run them by hand, turn it off too. |
| `codex: command not found` / broken symlink | `brew reinstall --cask codex` |
| `agy needs a model` | Pick one of the listed models |
| `jetski: no output produced … permission` | Call agy through the script, not directly |
| Very slow Antigravity run | The project and the temporary-copy folder must be under your home folder |
| `stage … LIMITED`, a `fallback:` line | An agent's quota ran out and the other agent took over. Codex is skipped up front once its usage passes 90% (`EXTERNAL_AGENT_CODEX_MAX_PCT`). To insist on one agent, `--no-fallback`. |
| `FINAL LIMITED` | Both agents are out of quota; the `limits:` line says when each resets |
| `install.ps1`: `-File parameter does not exist` / `SKILL.md not found` | Run it from the folder that contains it, or pass its full path |

Details: `external-agent/references/codex-cli.md` and `antigravity-cli.md`.

## Folder structure

```
external-agent/                 ← the skill (install this under ~/.claude/skills/)
├── SKILL.md                    ← the instructions Claude reads
├── scripts/
│   ├── agent_run.sh            ← delegate / task / resume / review / models
│   ├── implementer.schema.json ← agent report schema
│   └── review.schema.json      ← review findings schema
├── references/                 ← brief templates, CLI notes, manual mode
└── evals/                      ← 3 test scenarios (hidden tests included)
install.sh / install.ps1
```

You can rerun the test scenarios with `claude plugin eval` (Claude Code v2.1.269 or
later). These are real, paid model runs.

## License

MIT. See `LICENSE`.
