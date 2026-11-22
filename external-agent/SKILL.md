---
name: external-agent
description: Delegate coding work to external agent CLIs as sub-agents - OpenAI Codex CLI (GPT-6.2 Sol / Astra) and Google Antigravity CLI (agy, Gemini models). Claude writes a self-contained brief and dispatches it with one script call; the script has the agent implement, runs the verification command itself, gets an independent read-only review (optionally from the other agent family), sends real problems back to the same thread, and returns one status line. Claude only steps in on problems, keeping Claude's tokens for the heavy work. Use this whenever the user wants Codex, Antigravity, Gemini, GPT or another model to do part of the work or the simple chores - e.g. "have codex implement this", "give the chores to antigravity", "let gemini write the tests", "use an external agent", "outsource this to a subcontractor", "run the plan with codex", "have codex investigate this" - in whatever language the user writes, and when executing a multi-task plan where the user said these agents are available. Not for configuring the CLIs themselves.
---

# External Agent: Codex and Antigravity as sub-agents

You are the **controller**. External agent CLIs are your **subcontractors**: hand one a
task, get back a status, move on. Spend your own tokens on the hard parts (design,
tricky debugging, decisions) and let the subcontractors handle the chores. The
checking that makes this safe happens inside the pipeline, not in your context:

- the **verification command runs in the script**, so an agent's "tests pass" claim
  never counts by itself;
- a **fresh, read-only session reviews** every change against the brief. It never saw
  the implementer's reasoning, and it can come from the other agent family;
- critical/important findings and failing verification go **back to the same thread**
  automatically, for up to 2 fix rounds.

In testing, the independent review caught the real bugs (a fractional exactly-full
container rejected as overfull, a NaN slipping past a `<= 0` check, a clamp returning
`hi` for values below `lo`). Your reading every diff added little on top, at a high
token cost. So by default you don't read diffs or logs of tasks that come back `DONE`.

Script: `scripts/agent_run.sh` (relative to this skill's directory). Per-CLI notes and
troubleshooting: `references/codex-cli.md`, `references/antigravity-cli.md`.

## 1. The subcontractors

| | Codex (`--agent codex`) | Antigravity (`--agent agy`) |
|---|---|---|
| Models | `gpt-6.2-sol` (default), `gpt-6.2-astra` for hard work, `gpt-6-luna` for image tasks (`agent_run.sh models --agent codex`) | **user chooses** (see below); recommend Gemini 4 Neon, plus Gemini 4 Hydrogen for fast chores and images |
| Good for | Standard implementation, tests, reviews (Sol); hard work, debugging, investigations (Astra); images via its built-in image tool | Standard implementation, tests, reviews (Neon, Sol's equal); hard work as Astra's alternative; fast mechanical chores and images via its `image-generator` subagent (Hydrogen) |
| Isolation | Workspace-write sandbox; it *can* commit (the brief forbids it, the script warns) | Terminal sandbox, `.git` read-only, so it can't commit; reviews and investigations run in a disposable copy |
| Limits | Network off unless `--network` | Project must not be under `~/Library/Application Support`; needs the folder trusted in Antigravity (it is when under `$HOME` by default) |

**Routing (2026-11).** This rests on the vendors' launch material for GPT-6.2 (Nov 17)
and Gemini 4 Neon/Hydrogen (Nov 12-18), the user's experience with them, one
image-task test per CLI, and the `evals/` run of 2026-11-22: Sol and Neon each passed
every hidden test in all three scenarios with similar agent time, which backs treating
them as peers. One run per case, so not yet a large sample. Hydrogen and Luna were not
in those evals.

| Work | Who | Effort |
|---|---|---|
| Standard implementation: feature or bug fix in 1-3 files, writing tests, edge-case-heavy code | **Sol or Neon, as equals**: alternate between them, or pick the one with more quota left | Sol `medium`/`high`; `gemini-4-neon-medium` |
| Hard: multi-file integration, algorithmic or design-heavy work, tricky debugging | codex `gpt-6.2-astra`, or agy `gemini-4-neon-high/xhigh`; or keep it yourself | Astra `high`/`xhigh` (Sol at `max` if Codex quota is tight) |
| Fast mechanical chores with an exact spec: renames, moving code, formatting, docs, boilerplate, config edits | agy `gemini-4-hydrogen-low/medium` | |
| Image and asset generation (icons, sprites, textures, mockups, placeholder art) | agy `gemini-4-hydrogen-low` (Gemini's Nano Banana image model, via agy's `image-generator` subagent), or codex `gpt-6-luna` `low` (Codex's built-in image tool). See "Image tasks" in §4 | |
| Read-only investigation | codex `gpt-6.2-astra` `high` or agy `gemini-4-neon-high` | |
| Per-task review | the other family's peer (`--review-agent`, `--review-model`): Neon reviews Sol's work, Sol reviews Neon's; Astra (or Neon `high`) when the task was hard | review effort `high` |
| Final whole-change review | Astra or `gemini-4-neon-high`, from the family that implemented less | |

Why:

- **Sol and Neon are peers.** Both are their vendor's fast everyday model and do
  standard work equally well, so treat them as one pool. Splitting standard tasks
  between them stretches both quotas, and the other one makes a natural cross-family
  reviewer. At `max` effort Sol came within half a point of Astra on FrontierCode 2.0
  at about a fifth of the cost.
- **Hydrogen is fast, not as smart.** Google says it's about 2.5x faster than Gemini
  3.8 Flash, which it replaces, and it's the cheapest Gemini 4. But it reasons less
  than Sol or Neon, so give it only work where speed matters and thinking doesn't:
  exact-spec edits, and tool-driven jobs such as image generation, where the image
  model does the hard part. Never give it edge-case-heavy code, tests that must catch
  bugs, reviews or investigations.
- **Astra** is OpenAI's frontier model for long, hard work. It costs about four times
  as much as Sol per token, so it uses up the Codex quota faster. Keep it for hard
  tasks, investigations, and reviews of hard tasks.
- **Luna** (`gpt-6-luna`) is Codex's fast, cheap model. For image tasks the model only
  writes the prompt and saves the file, so a small model is enough.
- Neon is the newest and strongest Gemini 4 most accounts get. Carbon needs Google AI
  Ultra: route hard work to it only if `agy models` lists it. Argon still works and is
  the agy model this skill was measured with (below).
- The new Sol is reported to leave facts out of code Q&A answers (a 14-point drop on
  SWE-Atlas-QnA). That's why investigations go to Astra or Neon. When Sol reviews,
  give it effort `high` and the edge-case list in the review brief.

Both GPT-6.2 models also regressed on OpenAI's *Blocker Deception* test: they more
often fail to mention an obstacle (say, a file the brief names is missing) and work
around it quietly. The implementer brief asks for that to be reported, and the
script's verify and review steps catch what slips through. Read a `DONE_WITH_CONCERNS`
from Codex carefully.

**Review with the other model family.** That means the model, not the CLI: agy also
offers Claude and GPT-OSS models, and a Claude model reviewing for you, or a GPT model
checking Codex, isn't a second family. If the user names an agent or model, use it.

**Measured results (2026-10, previous models).** On the same three tasks (a two-task
plan, an edge-case-heavy parser, a read-only bug hunt), Codex/gpt-6.1-sol and
agy/Gemini 4 Argon reached the same quality: every hidden test passed, and both
handled the float and NaN traps. Argon took similar agent time with far fewer tokens.
Gemini 3.8 Flash was also correct, but 2-4x slower and used *more* tokens. These
models are all still available if the new ones misbehave.

**Choosing the Antigravity model.** Antigravity offers several model families. Its
non-Gemini models may be withdrawn, so don't hard-code one. The first time agy is
needed in a session, and the user hasn't named a model, run
`agent_run.sh models --agent agy`. Show the user the list and ask which models to use
(Gemini options first). Recommend Neon (`gemini-4-neon-medium`, `-high` for hard work)
for implementation, tests and reviews, and Hydrogen (`gemini-4-hydrogen-low`) for fast
mechanical chores and image generation.
Mention that Argon is the one already measured here. Reuse that answer for the rest of
the session. Without a model the script stops with exit 2 and prints the list, so it
never picks one silently. `EXTERNAL_AGENT_AGY_MODEL` sets a standing default if the
user wants one.

**Not used in the pipeline:** the `gemini-pro-orchestrator-*` models (they switch
models inside one session) and Codex's `ultra` effort ("automatic task delegation":
Codex starts its own sub-agents). Both delegate internally, which hasn't been tested
with the schema, resume and one-writer rules, so the script rejects `ultra`.
`gpt-6.1-terra` is built for visual understanding and computer use. It's an option for
a task that hinges on reading screenshots or images, otherwise use Sol.

## 2. Preflight (once per session)

1. Run `agent_run.sh doctor` **with the Bash sandbox disabled** (every `agent_run.sh`
   call needs that: inside Claude Code's sandbox Codex gets killed, exit 137 with no
   output, and agy can't reach its credentials, which looks like a broken install but
   isn't). Doctor checks each CLI's version against the latest release, compares the
   models each CLI offers with `scripts/models.tsv`, and makes a tiny "reply OK" probe
   run with each recommended model. A passed probe is cached per CLI version for 14
   days, so it costs quota only after an update. `--no-probe` skips the probes, and
   `--agent codex|agy` checks one CLI. `DOCTOR OK` means go ahead; an `info:` line
   under it (say, a Codex update is available) is worth one mention to the user. On
   `DOCTOR ATTENTION`, follow its `next:` lines:
   - **CLI too old for a recommended model** (the model is missing or its probe was
     rejected): tell the user and ask them to run `codex update` (or whatever
     installed it). Don't update a CLI yourself. Until then the script's Codex default
     falls back to the `fallback` model in `models.tsv` by itself (a `note:` says so),
     and wherever you would name a missing model, pass `--model`/`--review-model` with
     the one doctor names. agy updates itself in the background.
   - **Probe failed:** use the fallback model it names, or the other agent, and say so
     in your report.
   - **Routing may be stale** (a new model nobody has classified, or a recommended one
     that's gone): carry on with the task using what works, and tell the user in your
     report. Offer to refresh the skill: research the new models from the vendors'
     pages, update §1's table, `scripts/models.tsv` and `README.md`, then re-run
     `doctor` and, if the user agrees to the cost, `evals/run-headless.sh` (not
     `claude plugin eval`: its sandbox has no network, so Codex and agy never run and
     the case can still "pass"). Don't edit the skill
     mid-task without their go-ahead.

   If a CLI is missing, tell the user (Codex: `brew reinstall --cask codex` or
   `npm i -g @openai/codex`; agy: reinstall Antigravity). On Windows the script runs
   under Git Bash, the shell Claude Code's Bash tool uses there; it needs Python 3 as
   `python3` or `python`.
2. Check `git status --short` and the branch. If there are uncommitted changes that
   aren't yours, ask the user before stashing or committing them. Follow the host's
   branch conventions.
3. Decide how accepted work is recorded. If the user asked for commits, commit after
   each accepted task. Otherwise stage it (`git add <files>`), so staged means
   accepted and the next task's changes stay separate. Subcontractors never commit.
4. Run root: `<scratchpad>/agent-runs/` if you have a scratchpad, otherwise the
   script's default under `$TMPDIR`.

## 3. Plan and brief

Split the work into tasks and put them on your task list, each tagged with the agent
it goes to. Keep for yourself anything faster to do than to brief (under ~2 min),
decisions only the user can make, and anything involving secrets, deploys or pushes.

The brief is where your effort pays off. The agent knows nothing but the brief, and the
reviewer judges the work against it. Use `references/implementer-brief.md`. Above all,
write down the **edge cases** you would test (empty, zero/negative, NaN, float
precision, malformed input, boundaries). They steer both the implementer and the
reviewer. Name the files it may touch and forbid commits.

Pick a **verification command** the script can run from the repo root, e.g.
`python3 -m unittest discover -s tests -t .` or `npm test`. It should cover the new
behaviour, so ask the agent in the brief to add tests there. On Windows write `python`,
not `python3`: a python.org install has no `python3`, only the Microsoft Store stub.

| Effort | Use for |
|---|---|
| `low` | Mechanical edits with an exact spec |
| `medium` (default) | Typical feature or bug fix, 1-3 files |
| `high` | Multi-file integration, tricky edge cases, debugging, investigations |
| `xhigh` | Hard algorithmic/design work, or a retry after BLOCKED |
| `max` | The hardest tasks, or a retry after BLOCKED at `xhigh`. Slowest and most expensive. Sol's near-Astra coding results were measured at `max` |

`ultra` is rejected on purpose (see §1). agy model ids that end in
`-low/-medium/-high/-xhigh` already carry their effort level, and `--effort` is ignored
for them.

## 4. Delegate

```bash
scripts/agent_run.sh delegate --agent agy --model <chosen> \
  --review-agent codex --review-model gpt-6.2-astra \
  --cd <repo> --brief <brief.md> --verify "<test command>" \
  --name task-1 --effort medium --run-dir <run-root>/task-1
```

(`--agent codex` is the default; `--review-agent` defaults to the implementer's agent,
and `--review-model` to that agent's default or chosen model. For Codex that default
is Sol, so pass `--review-model gpt-6.2-astra` when Codex reviews, per §1.)

Run it with `run_in_background`. It takes 1-10 minutes, and you're notified when it
exits, so don't poll. Prepare the next brief meanwhile, but never start a second
**writer** in the same working tree (see §6).

**Usage limits.** Before using Codex, the script reads Codex's last recorded quota and
shows it on the `agents:` line (`usage: codex 5h=40% week=12%`). At 90% or more
(`EXTERNAL_AGENT_CODEX_MAX_PCT`) Codex is skipped. A step that fails with a usage-limit
error is marked `LIMITED`. Either way the role (implement or review) moves to the other
agent for the rest of the run: an implementer that takes over is told to check the
partial work in the tree, and gets the fix list if it was mid-fix. A fallback to agy
with no agy model chosen uses `EXTERNAL_AGENT_AGY_MODEL`, else `gemini-4-neon-medium`.
agy reports no usage figures, so its limits only show when a step fails. Pass
`--no-fallback` when the user insists on one agent.

**Image tasks.** Both CLIs generate images inside a normal `delegate` run: agy hands
the request to its built-in `image-generator` subagent (Gemini's Nano Banana model,
which checks its own result up to three times), and Codex uses its built-in image tool
(the `image_generation` feature, on by default). In the brief, give the subject, style,
background (transparent or a colour), size, file format and the exact path in the
project, and tell the agent to use its image tool rather than drawing with code. The
tools save elsewhere first (agy: `~/.gemini/antigravity-cli/brain/<conversation>/`, often
as JPEG; Codex: `~/.codex/generated_images/<thread>/`), so the brief must also ask for
the file to be copied, and converted if needed, to that path. Run with `--no-review`,
because a code reviewer can't judge a picture, and a `--verify` that checks the file
exists with the right format, e.g.
`python3 -c "import sys;sys.exit(open('assets/x.png','rb').read(8)!=b'\x89PNG\r\n\x1a\n')"`.
Then look at the image yourself (one Read of the file): that view is the review. If it
misses the brief, `resume` the same thread with what to change. Agents can't see the
picture's quality any better than you can.

For a read-only investigation, add `--sandbox read-only`. There's nothing to verify or
review then, and the answer comes back in the `answer:` line. Codex investigates in
its read-only sandbox; agy works in a disposable copy and may run code there. Check
the answer's key claim yourself with one cheap command (reproduce the bug, grep the
line), because nobody else reviews a read-only answer.

## 5. Act on the FINAL line

The output is an `agents:` line, a few `stage ...` lines, then `FINAL <status>`, any
`fallback:` and `limits:` lines, `files:`, any `concerns:` and `minor findings`, agent
token totals, and `git:`. A `fallback:` line means another agent took over a role:
mention it in your report, above all when the user had named the agent. An agent on
the `limits:` line stays out of quota until the reset time shown, so route the
session's next tasks elsewhere.

| FINAL | What to do |
|---|---|
| `DONE` | Check `files:` against the brief's scope (it's already in the output, no extra reads). Accept: stage or commit. Next task. |
| `DONE_WITH_CONCERNS` | Read the concerns line. A concern about correctness or scope (or an agent disputing a finding) needs a decision from you. Then accept, or resume with a fix. |
| `NEEDS_CONTEXT` | Answer the questions and resume the same thread: `agent_run.sh resume --agent <same> --thread <id> --brief <answers.md>`, then verify. |
| `BLOCKED` | Change something before retrying: more context, higher effort, a stronger model or the other agent, a smaller task, or do it yourself. The same brief gets the same result. |
| `NEEDS_ATTENTION` | Fix rounds ran out. Now open the referenced `verify.log` / `review.json`, and only those. Decide: fix it yourself if small, re-brief (perhaps to the other agent), or escalate to the user. |
| `LIMITED` | No agent had quota left (or `--no-fallback`). The `limits:` line says who ran out and when it resets; `git:` shows any partial work. Finish it yourself if small, otherwise tell the user and wait for the reset. |
| `FAILED` | The CLI itself errored. See the `stderr.log` named in the output and the CLI's reference file. |
| `WARNING: HEAD moved` | The agent committed despite the brief. Tell the user; rewriting history needs their go-ahead. |

`minor findings` are not fixed automatically. Fix them only if trivial, otherwise
list them in the final report. Don't stop to check in with the user between tasks.
Stop only for a blocker, a decision that's theirs, or a plan that turns out wrong.

**"Check each task" is what the pipeline does.** When the user says "check it" or
"check each one", the independent verify and review already are that check: report
them. Don't also re-run the suite, `cat` files or read diffs after a `DONE`. Those
re-checks cost your tokens and found nothing extra in testing.

**"Check thoroughly"** gets one addition, not manual mode. After
`DONE`, write a small probe script of adversarial inputs from the brief's edge cases
and your own ideas (malformed, boundary, unicode, huge, wrong type), run it, and
look only at its failures. Don't read the implementation or the agent's tests. Send
any failure back with `resume` (fix list = the failing inputs and expected results),
then re-run the probe and the verify command.

## 6. Parallelism

Writers run **one at a time per working tree**: two agents in one checkout corrupt
each other's diffs. Reviews and read-only investigations can run in parallel. To run
several subcontractors at once (say Codex on one feature, agy on tests for another),
give each independent task with disjoint files its own `git worktree add` directory
(its own `--cd`), and merge them back one by one after each comes back `DONE`.

## 7. Final check (once, at the end)

1. Run the whole test suite yourself, once. This is the one place you spend tokens
   on verification by default.
2. For multi-task work, run one review over the whole change, preferably from the
   family that did less of the implementing:
   `agent_run.sh review --agent <a> --model <m> --cd <repo> --uncommitted --brief <final-review.md>`
   (template in `references/review-brief.md`). Triage its findings against the code
   before acting.
3. Report to the user: a table with one row per task (agent/model, status, fix rounds,
   files), minor findings and concerns left open, anything you couldn't verify, agent
   token totals, and where the run logs are.

## When to check more closely: manual mode

Switch to step-by-step control with your own diff reading and testing for:
security, auth or payment code; data migrations or deletions; changes to public APIs;
a user who explicitly asks you to read or review the code yourself; or a task that
came back `NEEDS_ATTENTION` twice. The procedure (separate `task`, `review` and
`resume` calls, plus your own gates) is in `references/manual-mode.md`.
