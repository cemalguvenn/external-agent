---
name: external-agent
description: Delegate coding work to external agent CLIs as sub-agents - OpenAI Codex CLI (gpt-6.1-sol) and Google Antigravity CLI (agy, Gemini models). Claude writes a self-contained brief and dispatches it with one script call; the script has the agent implement, runs the verification command itself, gets an independent read-only review (optionally from the other agent family), sends real problems back to the same thread, and returns one status line. Claude only steps in on problems, keeping Claude's tokens for the heavy work. Use this whenever the user wants Codex, Antigravity, Gemini, GPT or another model to do part of the work or the simple chores - e.g. "have Codex implement this", "give the chores to Antigravity", "have Gemini do this", "use an external agent", "delegate the routine work", "implement the plan with Codex", "ask Codex to investigate" - and when executing a multi-task plan where the user said these agents are available. Not for configuring the CLIs themselves.
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
| Models | `gpt-6.1-sol` default (`agent_run.sh models --agent codex`) | **user chooses** (see below); prefer Gemini 4 Argon |
| Good for | Standard and hard implementation, debugging, investigations | Chores and standard implementation: tests, docs, boilerplate, refactors, small features; reviews; investigations |
| Isolation | Workspace-write sandbox; it *can* commit (the brief forbids it, the script warns) | Terminal sandbox, `.git` read-only, so it can't commit; reviews and investigations run in a disposable copy |
| Limits | Network off unless `--network` | Project must not be under `~/Library/Application Support`; needs the folder trusted in Antigravity (it is when under `$HOME` by default) |

**Routing.** In side-by-side tests on the same three tasks (a two-task plan, an
edge-case-heavy parser, a read-only bug hunt), Codex/gpt-6.1-sol and
agy/Gemini 4 Argon reached the same quality: every hidden test passed, and both
handled the float and NaN traps. Argon took similar agent time with far fewer
tokens. Gemini 3.8 Flash was also correct, but 2-4x slower and used *more* tokens, so
it is no cheaper in practice. Spread work across both subcontractors to stretch
both quotas. Send hard algorithmic or design-heavy work to Codex at `high`/`xhigh`,
or keep it yourself. When both CLIs are available, **review with the other family**
(`--review-agent`): a reviewer from a different model family has different blind
spots. If the user names an agent or model, use it.

**Choosing the Antigravity model.** Antigravity offers several model families. Its
non-Gemini models may be withdrawn, so don't hard-code one. The first time agy is
needed in a session, and the user hasn't named a model, run
`agent_run.sh models --agent agy`. Show the user the list and ask which model to use
for implementation and which (if any) for reviews, Gemini options first. Recommend
Argon, and mention Flash's measured slowness if they lean that way. Reuse that answer for
the rest of the session. Without a model the script stops with exit 2 and prints the
list, so it never picks one silently. `EXTERNAL_AGENT_AGY_MODEL` sets a standing
default if the user wants one.

## 2. Preflight (once per session)

1. Run `codex --version` and/or `agy --version` **with the Bash sandbox disabled**.
   Inside Claude Code's sandbox Codex gets killed (exit 137, empty output) and agy
   can't reach its credentials, which looks like a broken install but isn't. Every
   `agent_run.sh` call needs the sandbox disabled too. If a CLI is missing, tell the
   user (Codex: `brew reinstall --cask codex` or `npm i -g @openai/codex`; agy:
   `agy update` or reinstall Antigravity). On Windows the script runs under Git Bash,
   the shell Claude Code's Bash tool uses there; it needs Python 3 as `python3` or
   `python`.
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

agy model ids that end in `-low/-medium/-high` already carry their effort level, and
`--effort` is ignored for them.

## 4. Delegate

```bash
scripts/agent_run.sh delegate --agent agy --model <chosen> --review-agent codex \
  --cd <repo> --brief <brief.md> --verify "<test command>" \
  --name task-1 --effort medium --run-dir <run-root>/task-1
```

(`--agent codex` is the default; `--review-agent` defaults to the implementer's agent,
and `--review-model` to that agent's default or chosen model.)

Run it with `run_in_background`. It takes 1-10 minutes, and you're notified when it
exits, so don't poll. Prepare the next brief meanwhile, but never start a second
**writer** in the same working tree (see §6).

**Usage limits.** Before using Codex, the script reads Codex's last recorded quota and
shows it on the `agents:` line (`usage: codex 5h=40% week=12%`). At 90% or more
(`EXTERNAL_AGENT_CODEX_MAX_PCT`) Codex is skipped. A step that fails with a usage-limit
error is marked `LIMITED`. Either way the role (implement or review) moves to the other
agent for the rest of the run: an implementer that takes over is told to check the
partial work in the tree, and gets the fix list if it was mid-fix. A fallback to agy
with no agy model chosen uses `EXTERNAL_AGENT_AGY_MODEL`, else `gemini-4-argon-medium`.
agy reports no usage figures, so its limits only show when a step fails. Pass
`--no-fallback` when the user insists on one agent.

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

**"Check each task" is what the pipeline does.** When the user says "check each one",
the independent verify and review already are that check: report
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
