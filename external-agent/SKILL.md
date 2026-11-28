---
name: external-agent
description: Collective multi-AI orchestration across all three major model families — Anthropic Claude Code CLI (Opus / Sonnet), Google Antigravity CLI (agy: Gemini 4 Neon / Carbon / Hydrogen + Nano Banana), and OpenAI Codex CLI (GPT-6.2 Sol / Astra + Luna image) — working from either Claude Code or Antigravity as host. The host writes a self-contained brief and dispatches work with one script call; the script implements, runs the verification command itself, gets an independent cross-family read-only review, sends real problems back to the same thread, and returns one status line. Use this whenever the user wants to share coding, review, web research, or image generation work across Opus, Neon, Sol, Astra, Carbon, Sonnet, Hydrogen, Codex, Antigravity, Gemini, or GPT — e.g. "have codex implement this", "share the load with neon/opus", "let sol write the tests", "have carbon/astra review this", "generate mockups with codex and nano banana", "use hydrogen for quick web research/chores", "run the plan with external agents" — in whatever language the user writes, and when executing a multi-task plan where these agents are available. Not for configuring the CLIs themselves.
---

# External Agent: Collective 3-AI Orchestration (Claude, Antigravity, Codex)

You are the **host controller** — **Opus** when running inside Claude Code, or **Neon** when
running inside Antigravity. Instead of doing everything in one model family and burning one
quota, you coordinate a **collective of all three major AI families** (`claude`, `agy`, `codex`)
so every model works where it is strongest and usage limits stretch as far as possible.

The checking that makes delegation safe happens inside the pipeline, not in your context:

- the **verification command runs in the script**, so an agent's "tests pass" claim
  never counts by itself;
- a **fresh, read-only session reviews** every change against the brief. It never saw
  the implementer's reasoning, and it comes from a **different model family**;
- critical/important findings and failing verification go **back to the same thread**
  automatically, for up to 2 fix rounds.

In testing, the independent review caught the real bugs (a fractional exactly-full
container rejected as overfull, a NaN slipping past a `<= 0` check, a clamp returning
`hi` for values below `lo`). Reading every diff yourself added little on top, at a high
token cost. So by default you don't read diffs or logs of tasks that come back `DONE`.

Script: `scripts/agent_run.sh` (relative to this skill's directory). Per-CLI notes and
troubleshooting: `references/claude-cli.md`, `references/codex-cli.md`,
`references/antigravity-cli.md`.

## 1. The collective and routing

| | Claude (`--agent claude`) | Antigravity (`--agent agy`) | Codex (`--agent codex`) |
|---|---|---|---|
| Models | `opus` (default, co-lead), `sonnet` (fast economical helper) | **user chooses** (see below); `gemini-4-neon` (co-lead), `gemini-4-hydrogen` (fast helper & Nano Banana images), `gemini-4-carbon` (critical reviewer when listed) | `gpt-6.2-sol` (default workhorse), `gpt-6.2-astra` (critical reviewer & hard debugging), `gpt-6-luna` (Codex image tool) |
| Good for | Heavy coding, architecture, code-generated visuals, final approval, standard reviews (`opus`); light/medium edits & docs (`sonnet`) | Heavy coding, code-generated visuals, final approval, standard reviews, investigations (`neon`); web search, mechanical chores & Nano Banana images (`hydrogen`); critical reviews (`carbon`) | Standard/light implementation, tests, routine bug fixes (`sol`); critical reviews, hard debugging & investigations (`astra`); raster images (`luna`) |
| Isolation | Headless `claude -p` (`--disable-slash-commands`); reviews & read-only runs use a disposable copy | Terminal sandbox, `.git` read-only; reviews & read-only runs use a disposable copy | Workspace-write sandbox (brief forbids commits, script warns); native `read-only` sandbox |
| Limits | Strip nested `CLAUDECODE` env vars (script handles this) | Project must not be under `~/Library/Application Support`; folder must be trusted in Antigravity (under `$HOME` by default) | Network off unless `--network` |

**Host-aware load balancing (Co-leads: Opus & Neon).**
Opus and Neon sit at the same flagship tier. Whichever platform you are running on carries
the primary load (orchestrating, approving reports, taking the core tasks), while **always
sharing part of the heavy workload** with the other co-lead so both quotas stay balanced
and work gets cross-family eyes:

- **When running in Claude Code** (`--host claude`): **Opus** is the primary carrier;
  delegate a meaningful share of heavy coding, independent reviews, and code-generated
  visuals to **Neon** (`--agent agy --model gemini-4-neon-medium/high`).
- **When running in Antigravity** (`--host agy`): **Neon** is the primary carrier;
  delegate a meaningful share of heavy coding, independent reviews, and code-generated
  visuals to **Opus** (`--agent claude --model opus`).
- **Never use Antigravity's built-in Claude models** (`claude-opus-*`, `claude-sonnet-*`
  inside `agy`): always call Claude directly via `--agent claude` so each vendor's quota
  is used cleanly.

**Routing table (2026-11).** Built on vendor capabilities, hands-on testing, and the
2026-11-22 `evals/` benchmark (where Sol and Neon each passed 100% of hidden tests).

| Work | Who | Effort |
|---|---|---|
| **Heavy / core coding, architecture, tricky integration, final approval of reports** | **Co-leads: Opus & Neon.** Host takes the primary share, delegates independent heavy modules to the other co-lead (`claude opus` or `agy gemini-4-neon-high`) | `high` / `xhigh` |
| **Code-generated visual content** (SVG, Canvas, WebGL/Three.js, CSS/HTML UI, shaders, charts, procedural art) | **Co-leads only: Opus or Neon** (never Sol, Hydrogen, or raster image tools) | `medium` / `high` |
| **Light-to-standard coding**: 1-3 file features, routine bug fixes, writing tests, standard refactors | **Workhorse: `codex` `gpt-6.2-sol`** (or `claude sonnet` for light edits/docs when Codex quota is tight) | Sol `medium`/`high`; Sonnet `medium` |
| **Fast & economical chores + web search**: quick web lookups, exact-spec mechanical edits (renames, moving code, formatting, boilerplate, config), docs/summaries | **`agy` `gemini-4-hydrogen-low/medium`** (especially web search & mechanical chores) or **`claude` `sonnet`** (light edits, docs, summaries) | `low` / `medium` |
| **Raster / AI image & asset generation** (icons, sprites, textures, illustrations, mockups) | **Nano Banana** (`agy` `gemini-4-hydrogen-low` via `image-generator`, or Antigravity's built-in `image-generator` when Antigravity is host) & **Codex Image** (`codex` `gpt-6-luna` `low`). Use A/B mockup bake-off for important visuals (see §4) | `low` |
| **Read-only investigation / bug hunt** | `agy` `gemini-4-neon-high`, `claude` `opus`, or `codex` `gpt-6.2-astra` `high` | `high` |
| **Standard per-task review** (routine / non-critical tasks) | **Co-leads (Opus or Neon), cross-family**: Neon reviews Sol/Opus work; Opus reviews Sol/Neon work | `high` |
| **Critical-task review & final whole-change review** | **Heavyweight reviewers (cross-family): `agy` `gemini-4-carbon`** (if offered by `agy models`, else `gemini-4-neon-high/xhigh`) and/or **`codex` `gpt-6.2-astra`**. Pick the family that wrote less of the code | `high` / `xhigh` |

Why:

- **Opus and Neon are co-leads.** Both deliver top-tier coding, reasoning, visual-code
  craft, and report triage. Splitting heavy work and standard reviews between them keeps
  neither quota exhausted and gives genuine cross-family verification.
- **GPT-6.2 Sol is the workhorse.** Fast, reliable, and ~1/4–1/5 the cost of Astra. It
  handles standard implementation and test writing cleanly, freeing Opus and Neon for
  core architecture and reviews. Note: Sol regressed on code Q&A (SWE-Atlas-QnA), so send
  read-only investigations to Neon, Opus, or Astra.
- **GPT-6.2 Blocker Deception caution:** Both GPT-6.2 models (Sol, Astra) are more likely
  to work around a missing file or obstacle quietly instead of flagging it. The brief
  template explicitly requires reporting obstacles, and verify + review catch what slips
  through. Read `DONE_WITH_CONCERNS` from Codex carefully.
- **Hydrogen & Sonnet are the fast, economical helpers.** Hydrogen (~2.5x faster than
  Gemini 3.8 Flash, cheapest Gemini 4) excels at **web search / quick lookups**, exact-spec
  mechanical chores, and dispatching Nano Banana image generation. Never give Hydrogen
  edge-case-heavy code, bug-catching tests, or code reviews. Sonnet is the fast Claude-family
  helper for light/medium edits, docs, and summaries.
- **Carbon & Astra are reserved for high-stakes reviews.** Astra costs ~4x Sol per token,
  and Carbon requires Google AI Ultra. Save them for critical/high-risk tasks and final
  whole-change reviews rather than routine per-task checks.
- **Luna (`gpt-6-luna`)** is Codex's fast, cheap model — ideal for Codex image tasks where
  the image tool does the drawing.

**Cross-family review rule.** Always review with a **different model family** than the
implementer (Claude vs Gemini vs GPT). `agy` also lists `gpt-oss-120b` and Claude models;
those are never used as cross-family reviewers.

**Choosing the Antigravity model.** When `agy` is first needed as an external CLI in a
session and the user hasn't named a model (and `EXTERNAL_AGENT_AGY_MODEL` is unset), run
`agent_run.sh models --agent agy`, show the Gemini options first, and ask which to use
(recommend `gemini-4-neon-medium` / `-high` for co-lead work, `gemini-4-hydrogen-low` for
chores/web/images, and note `gemini-4-carbon` if listed for critical reviews). Reuse that
choice for the session. Without a model the script exits 2 and prints the list.

**Not used in the pipeline:** `gemini-pro-orchestrator-*`, `agy`'s `claude-*` models, and
Codex's `ultra` effort (internal sub-agent delegation, rejected by the script).

## 2. Preflight (once per session)

1. Run `agent_run.sh doctor` **with the host sandbox disabled** (every `agent_run.sh` call
   needs that: in Claude Code disable the Bash sandbox — otherwise Codex exits 137 and agy
   cannot reach credentials; in Antigravity pass `BypassSandbox: true`).
   Doctor checks `codex`, `agy`, and `claude`: CLI versions against latest releases,
   offered models against `scripts/models.tsv`, whether `gemini-4-carbon` is unlocked,
   and a tiny "reply OK" probe per recommended model (cached 14 days per CLI version).
   `--no-probe` skips probes; `--agent codex|agy|claude|all` checks specific CLIs.
   - `DOCTOR OK`: proceed (mention any `info:` line once to the user).
   - `DOCTOR ATTENTION`: follow its `next:` lines:
     - **CLI too old for a recommended model:** tell the user (`codex update` / `claude update`);
       never update CLIs yourself. Use the fallback model until updated.
     - **Probe failed:** use the named fallback or another available family, and mention it
       in your final report.
     - **Routing may be stale** (new or removed model): finish the user's task with what
       works, note it in your report, and offer to refresh the skill (`SKILL.md`,
       `scripts/models.tsv`, `README.md`, `README.tr.md`) afterwards.
   - If a CLI is missing, tell the user (Codex: `brew reinstall --cask codex` or
     `npm i -g @openai/codex`; Antigravity: install Antigravity; Claude: `claude install` /
     `npm i -g @anthropic-ai/claude-code`). On Windows the script runs under Git Bash and
     needs Python 3 (`python` or `python3`).
2. Check `git status --short` and the branch. If there are uncommitted changes that
   aren't yours, ask the user before stashing or committing them.
3. Decide how accepted work is recorded. If the user asked for commits, commit after
   each accepted task. Otherwise stage it (`git add <files>`), so staged means
   accepted and the next task's changes stay separate. Subcontractors never commit.
4. Pass `--host claude` (when running in Claude Code) or `--host agy` (when running in
   Antigravity), or set `EXTERNAL_AGENT_HOST`, so automatic quota fallback never tries to
   recursively delegate back to the host's own CLI.
5. Run root: `<scratchpad>/agent-runs/` if you have a scratchpad, otherwise the
   script's default under `$TMPDIR`.

## 3. Plan and brief

Split the work into tasks and tag each with its assigned model/family according to §1.
Keep for yourself anything faster to do than to brief (under ~2 min), decisions only the
user can make, and anything involving secrets, deploys or pushes.

The brief is where your effort pays off. The external agent knows nothing but the brief,
and the reviewer judges the work against it. Use `references/implementer-brief.md`. Above
all, write down the **edge cases** you would test (empty, zero/negative, NaN, float
precision, malformed input, boundaries). Name the files it may touch and forbid commits.

Pick a **verification command** the script can run from the repo root, e.g.
`python3 -m unittest discover -s tests -t .` or `npm test`. Ask the agent in the brief to
add tests covering every acceptance criterion. On Windows write `python`, not `python3`.

| Effort | Use for |
|---|---|
| `low` | Mechanical edits with an exact spec, image dispatch, quick web lookups |
| `medium` (default) | Typical feature or bug fix, 1-3 files |
| `high` | Multi-file integration, tricky edge cases, debugging, investigations, reviews |
| `xhigh` | Hard algorithmic/design work, critical reviews, or a retry after `BLOCKED` (mapped to `max` for `claude`) |
| `max` | Hardest tasks, or a retry after `BLOCKED` at `xhigh`. Slowest and most expensive |

`ultra` is rejected on purpose. `agy` model IDs ending in `-low/-medium/-high/-xhigh`
already carry their effort level (`--effort` is ignored for them).

## 4. Delegate

```bash
# Example from Claude Code (--host claude): Sol implements, Neon reviews
scripts/agent_run.sh delegate --host claude \
  --agent codex --model gpt-6.2-sol \
  --review-agent agy --review-model gemini-4-neon-high \
  --cd <repo> --brief <brief.md> --verify "<test command>" \
  --name task-1 --effort medium --run-dir <run-root>/task-1

# Example from Antigravity (--host agy): Opus implements heavy module, Astra reviews (critical)
scripts/agent_run.sh delegate --host agy \
  --agent claude --model opus \
  --review-agent codex --review-model gpt-6.2-astra \
  --cd <repo> --brief <brief.md> --verify "<test command>" \
  --name core-engine --effort high --run-dir <run-root>/core-engine
```

Run it in the background (it takes 1-10 minutes; you're notified on completion, so don't
poll). Prepare the next brief meanwhile, but never start a second **writer** in the same
working tree (see §6).

**Usage limits & 3-way fallback.** Before using Codex, the script reads Codex's last
recorded quota (`usage: codex 5h=40% week=12%`) and skips Codex at 90% or more
(`EXTERNAL_AGENT_CODEX_MAX_PCT`). Any step that fails with a usage-limit / quota error is
marked `LIMITED`, and its role moves to another installed, non-limited external agent
(skipping `--host` so the host isn't called recursively). If no external agent has quota
left, the run ends `FINAL LIMITED` so the host can decide whether to finish it directly or
wait for reset. Pass `--no-fallback` when the user insists on one specific agent.

**Visual & image tasks.**
- **Code-generated visuals** (SVG, Canvas, WebGL/Three.js, CSS/HTML, charts): route only
  to **Opus or Neon** as normal coding tasks.
- **Raster / AI-generated images** (icons, sprites, textures, illustrations, UI mockups):
  - **Nano Banana:** via `agy` (`--agent agy --model gemini-4-hydrogen-low`, using its
    built-in `image-generator` subagent) — or, when Antigravity is the host, directly via
    your own `image-generator` subagent.
  - **Codex Image:** via `codex` (`--agent codex --model gpt-6-luna --effort low`, using
    Codex's built-in `image_generation` tool).
  - In the brief, specify subject, style, background (transparent or colour), size, file
    format, and exact output path in the project, and instruct the agent to use its image
    tool (not draw with code) and copy/convert the output to that exact path (agy saves
    under `~/.gemini/antigravity-cli/brain/<conversation>/`; Codex under
    `~/.codex/generated_images/<thread>/`).
  - Run with `--no-review` (code reviewers cannot judge images) and a `--verify` check
    that confirms the file exists with the right format, e.g.
    `python3 -c "import sys;sys.exit(open('assets/x.png','rb').read(8)!=b'\x89PNG\r\n\x1a\n')"`.
- **A/B Mockup Bake-off (for important visual tasks or multi-asset packs):**
  1. Dispatch 1 mockup of the hero asset to **both** Codex Image (`assets/mockup-codex.png`)
     and Nano Banana (`assets/mockup-banana.png`) in parallel (disjoint output paths).
  2. Have a **co-lead (Opus or Neon)** judge both mockups — either inspect both files
     directly yourself with `read_file`, or delegate the comparison to the *other* co-lead
     for an independent pick (pick based on brief adherence, style quality, and cleanliness).
  3. Clean up the rejected mockup and assign the remaining visual assets to the **winning
     image model** (resuming its thread or referencing the winning mockup for style
     consistency).

**Fast web search / research chores.** For quick external lookups (API docs, library
versions, error lookup) that don't justify spending Opus/Neon/Astra quota, dispatch a
read-only task to `agy` `gemini-4-hydrogen-low` (`--sandbox read-only`) — or use the
host's own web search if it's a single trivial query.

**Read-only code investigations.** Add `--sandbox read-only` (verify and review are
skipped; the answer comes back in `answer:`). Route to `agy` `gemini-4-neon-high`,
`claude` `opus`, or `codex` `gpt-6.2-astra` `high`. Check the answer's key claim yourself
with one cheap command (reproduce the bug, grep the line).

## 5. Act on the FINAL line

The output has `agents:`, `stage ...` lines, `FINAL <status>`, any `fallback:` and
`limits:` lines, `files:`, `concerns:`, `minor findings`, agent token totals, and `git:`.
A `fallback:` line means another agent took over a role — mention it in your report. An
agent on `limits:` stays out of quota until the reset time shown, so route the session's
next tasks elsewhere.

| FINAL | What to do |
|---|---|
| `DONE` | Check `files:` against the brief's scope (already in output, no extra reads). Accept: stage or commit. Next task. |
| `DONE_WITH_CONCERNS` | Read the concerns line. A concern about correctness or scope (or a disputed finding) needs a decision from you. Then accept, or resume with a fix. |
| `NEEDS_CONTEXT` | Answer the questions and resume the same thread: `agent_run.sh resume --agent <same> --thread <id> --brief <answers.md>`, then verify. |
| `BLOCKED` | Change something before retrying: more context, higher effort, a co-lead or another family, a smaller task, or do it yourself. |
| `NEEDS_ATTENTION` | Fix rounds ran out. Open only the referenced `verify.log` / `review.json`. Decide: fix it yourself if small, re-brief (perhaps to another family), or escalate to the user. |
| `LIMITED` | No external agent had quota left (or `--no-fallback`). Check `limits:` and `git:`. Finish it yourself if small, otherwise tell the user and wait for the reset. |
| `FAILED` | The CLI itself errored. See the `stderr.log` named in the output and the CLI's reference file. |
| `WARNING: HEAD moved` | The agent committed despite the brief. Tell the user; rewriting history needs their go-ahead. |

`minor findings` are not fixed automatically. Fix them only if trivial, otherwise list
them in the final report. Don't stop to check in with the user between tasks — stop only
for a blocker, a user decision, or a plan that turns out wrong.

**"Check each task" is what the pipeline does.** Don't re-run the suite, `cat` files, or
read diffs after a `DONE`.

**"Check thoroughly"** gets one addition, not manual mode: after `DONE`, write a small
probe script of adversarial inputs from the brief's edge cases, run it, and look only at
its failures. Send any failure back with `resume`, then re-run the probe and verify.

## 6. Parallelism

Writers run **one at a time per working tree**: two writers in one checkout corrupt each
other's diffs. Reviews, read-only investigations, and A/B mockups writing to disjoint
files can run in parallel. To run several coding agents at once (e.g. Sol on tests, Opus
or Neon on a separate module), give each independent task with disjoint files its own
`git worktree add` directory (its own `--cd`), and merge them back one by one after each
comes back `DONE`.

## 7. Final check (once, at the end)

1. Run the whole test suite yourself, once.
2. For multi-task or critical work, run one **heavyweight whole-change review** using
   **Carbon** (`agy` `gemini-4-carbon`, if available, else `gemini-4-neon-high`) or
   **Astra** (`codex` `gpt-6.2-astra` `--effort high`), from the family that did less of
   the implementing:
   `agent_run.sh review --agent <a> --model <m> --cd <repo> --uncommitted --brief <final-review.md>`
   (template in `references/review-brief.md`). Triage its findings against the code before
   acting.
3. Report to the user: a table with one row per task (agent/model, reviewer, status, fix
   rounds, files), minor findings and concerns left open, anything you couldn't verify,
   agent token totals, and where the run logs are.

## When to check more closely: manual mode

Switch to step-by-step control with your own diff reading and testing for: security, auth
or payment code; data migrations or deletions; changes to public APIs; a user who
explicitly asks you to read or review the code yourself; or a task that came back
`NEEDS_ATTENTION` twice. The procedure is in `references/manual-mode.md`.
