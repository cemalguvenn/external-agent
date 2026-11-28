# external-agent

**English** · [Türkçe](README.tr.md)

**Collective 3-AI orchestration skill for Claude Code and Antigravity.**
Run from either **Claude Code (Opus)** or **Antigravity (Gemini 4 Neon)** as host, and
distribute work across all three major agent CLIs based on each model's strengths:

- **Anthropic Claude Code CLI (`claude`):** Co-lead flagship **Opus** (`opus`), fast economical helper **Sonnet** (`sonnet`)
- **Google Antigravity CLI (`agy`):** Co-lead flagship **Gemini 4 Neon**, fast/economical helper & web search & Nano Banana images **Hydrogen**, critical reviewer **Carbon**
- **OpenAI Codex CLI (`codex`):** Workhorse **GPT-6.2 Sol**, critical reviewer & hard debugging **GPT-6.2 Astra**, image tool **Luna**

Every delegated task is verified independently and reviewed by a **different model family**.
Opus and Neon carry core coding, code-generated visuals, standard reviews, and final
approvals while stretching usage quotas cleanly across all three platforms.

---

## How it works

For each task, the host writes a self-contained brief and dispatches it with one command:

```
Host (Opus / Neon) ──brief──▶ agent_run.sh delegate
                                │
                                ├─ 0. quota     : checks Codex usage (skips Codex at 90%+)
                                ├─ 1. implement : claude / agy / codex writes the code (never commits)
                                ├─ 2. verify    : the SCRIPT runs the test command independently
                                ├─ 3. review    : fresh, read-only session from another model family
                                ├─ 4. fix       : critical/important findings go back to the same thread (up to 2 rounds)
                                │   (if an agent runs out of quota, another available external CLI takes over)
                                └─ FINAL DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED | NEEDS_ATTENTION | LIMITED | FAILED
Host ◀── one status line + changed files + open notes
```

On `DONE`, the host doesn't waste tokens re-reading diffs; it moves on to the next task.
At the end, it runs the full test suite once and runs a final whole-change review.

### Quota & 3-way fallback

- **Before starting:** Codex records its 5-hour and weekly quota in its session files.
  The script reads the latest value (`usage: codex 5h=40% week=12%`) and skips Codex at
  90% or more (`EXTERNAL_AGENT_CODEX_MAX_PCT`).
- **Mid-run:** If any CLI hits a usage or rate limit, that stage is marked `LIMITED` and
  the role moves to another installed, non-limited external CLI (skipping `--host` so the
  host isn't called recursively).
- **If all external CLIs are out:** the run ends `FINAL LIMITED` with reset info on the
  `limits:` line. Pass `--no-fallback` to insist on one specific agent.

---

## Task routing

The skill balances the flagship load by host: **Neon** carries the primary load in
Antigravity, **Opus** carries it in Claude Code, and they always share part of the heavy
workload across families (`agy`'s bundled Claude models are never used — Claude tasks
always go through `--agent claude`).

| Work | Who |
|---|---|
| **Heavy / core coding, architecture, final approval of reports** | **Co-leads: Opus & Neon.** Host carries the primary load and delegates independent heavy modules to the other co-lead (`claude opus` / `agy gemini-4-neon-high`) |
| **Code-generated visual content** (SVG, Canvas, WebGL/Three.js, CSS/HTML UI, shaders, charts) | **Co-leads only: Opus or Neon** |
| **Light-to-standard coding:** 1–3 file features, routine bug fixes, writing tests, refactors | **Workhorse: `codex` `gpt-6.2-sol`** (`medium`/`high`) |
| **Fast & economical chores + web search:** quick web lookups, exact-spec mechanical edits, docs/summaries | **`agy` `gemini-4-hydrogen-low/medium`** (especially web search & mechanical chores) or **`claude` `sonnet`** (light edits, docs, summaries) |
| **Raster / AI image & asset generation:** icons, sprites, textures, mockups | **Nano Banana** (`agy` `gemini-4-hydrogen-low` / `image-generator`) & **Codex Image** (`codex` `gpt-6-luna` `low`) |
| **Read-only code investigation** | `agy` `gemini-4-neon-high`, `claude` `opus`, or `codex` `gpt-6.2-astra` `high` |
| **Standard per-task review** | **Co-leads (Opus / Neon), cross-family:** Neon or Opus reviews Sol; Neon reviews Opus; Opus reviews Neon |
| **Critical-task review & final whole-change review** | **Heavyweight reviewers (cross-family): `agy` `gemini-4-carbon`** (when listed, else `gemini-4-neon-high/xhigh`) and/or **`codex` `gpt-6.2-astra`** |

### Visual tasks & A/B Mockup Bake-off

- **Code-generated visuals** (SVG, Canvas, Three.js, shaders, charts) always stay with
  **Opus** or **Neon**.
- **Raster / AI-generated visuals** use **Nano Banana** and **Codex Image** (`--no-review`
  + format-checking `--verify`).
- **A/B Mockup Bake-off:** For important visuals or multi-asset packs, generate 1 mockup
  from **both** Codex Image and Nano Banana in parallel. A **co-lead** (the host or the
  other co-lead) inspects both mockups, picks the winner, and assigns the remaining visual
  tasks to the winning model.

---

## Keeping itself current: `doctor`

At the start of each session, the host runs `agent_run.sh doctor`:

1. **CLI versions:** compares installed `codex`, `agy`, and `claude` versions against
   latest releases.
2. **Model catalog:** compares offered models against `scripts/models.tsv` (and reports if
   `gemini-4-carbon` is unlocked on the account).
3. **Probe runs:** sends a tiny "reply OK" probe per recommended model (cached 14 days per
   CLI version, so quota is only used after updates).

```bash
S=~/.claude/skills/external-agent/scripts/agent_run.sh
$S doctor                            # full check (codex, agy, claude)
$S doctor --no-probe                 # free checks only
$S doctor --agent codex --reprobe    # ignore cache and probe again
```

---

## Requirements & Installation

| | macOS / Linux | Windows |
|---|---|---|
| Host | Claude Code and/or Antigravity | same |
| bash | built in | **Git for Windows** (Git Bash) |
| Python 3.8+ | `python3` | `python` (Microsoft Store stub is skipped) |
| git | ✓ | ✓ (comes with Git for Windows) |
| Agent CLIs | `claude`, `codex`, `agy` (signed in) | same |

### macOS / Linux

```bash
git clone https://github.com/cemalguvenn/external-agent.git
cd external-agent
./install.sh --link --force                  # symlinks to Claude Code + Antigravity (if present)
./install.sh --target claude|agy|both        # install to a specific platform
```

### Windows (PowerShell)

```powershell
git clone https://github.com/cemalguvenn/external-agent.git
powershell -ExecutionPolicy Bypass -File .\external-agent\install.ps1 -Force
# Optional: -Target claude | agy | both
```

Restart Claude Code / Antigravity after installing.

---

## Usage

Ask naturally in any language; the skill activates on its own:

- "run the tasks in plan.md with external agents, share heavy parts between opus and neon, let sol write the tests"
- "have carbon or astra do a critical review of the auth changes"
- "use hydrogen to quickly check the latest API docs and update the config"
- "generate two hero icon mockups with codex and nano banana, pick the best one and make the rest of the set"
- "build the interactive SVG/Canvas chart yourself or with the other co-lead"

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `EXTERNAL_AGENT_MODEL` | `gpt-6.2-sol` | Default Codex model |
| `EXTERNAL_AGENT_AGY_MODEL` | (asked once per session) | Default Antigravity model (e.g. `gemini-4-neon-medium`) |
| `EXTERNAL_AGENT_CLAUDE_MODEL` | `opus` | Default Claude CLI model (`opus` or `sonnet`) |
| `EXTERNAL_AGENT_HOST` | (none) | Host platform (`claude` or `agy`); skipped by automatic fallback |
| `EXTERNAL_AGENT_CODEX_MAX_PCT` | `90` | Skip Codex when 5h or weekly usage reaches this % |
| `EXTERNAL_AGENT_RUNS` | `$TMPDIR/external-agent` | Root folder for run logs |
| `EXTERNAL_AGENT_SNAP_ROOT` | `~/.cache/external-agent` | Temporary copies for Antigravity & Claude read-only runs |

### Calling the script directly

```bash
S=~/.claude/skills/external-agent/scripts/agent_run.sh
$S doctor
$S models --agent agy
$S delegate --host claude --agent codex --model gpt-6.2-sol \
   --review-agent agy --review-model gemini-4-neon-high \
   --cd ~/project --brief task.md --verify "npm test" --name task-1
$S delegate --host agy --agent claude --model opus \
   --review-agent codex --review-model gpt-6.2-astra \
   --cd ~/project --brief core.md --verify "pytest" --name core-1
```

---

## Safety & limits

- **Subcontractors never commit.** The brief forbids commits, the script warns if `HEAD`
  moves, and Antigravity's sandbox makes `.git` read-only.
- **Read-only isolation:** Codex uses its native `read-only` sandbox; Antigravity and
  Claude run reviews and read-only investigations in a disposable project copy that is
  deleted afterwards.
- **Manual mode:** For security, auth, payments, data migrations, or public API changes,
  the host switches to step-by-step control and reads/tests the diffs itself.
- **Host sandbox:** Run `agent_run.sh` with the host's shell sandbox disabled (Claude Code:
  Bash sandbox off; Antigravity: `BypassSandbox: true`) so child CLIs can reach their
  credentials and network.

Details and per-CLI troubleshooting: `external-agent/references/claude-cli.md`,
`codex-cli.md`, and `antigravity-cli.md`.

## Folder structure

```
external-agent/                 ← skill (installed to ~/.claude/skills/ and/or ~/.gemini/config/skills/)
├── SKILL.md                    ← instructions read by the host (Claude Code / Antigravity)
├── scripts/
│   ├── agent_run.sh            ← delegate / task / resume / review / models / doctor
│   ├── doctor.py               ← CLI version, model catalog, and probe checks
│   ├── models.tsv              ← known models and roles across claude, codex, agy
│   ├── implementer.schema.json ← structured implementer report schema
│   └── review.schema.json      ← structured review findings schema
├── references/                 ← brief templates, per-CLI notes, manual mode
└── evals/                      ← headless evaluation harness and test cases
install.sh / install.ps1
```

## License

MIT. See `LICENSE`.
