# Manual mode: step-by-step control

Use this instead of `delegate` when the stakes justify spending your own tokens on
verification: security, auth or payment code; data migrations or deletions; public API
changes; an explicit request from the user for careful checking; or a task that came
back `NEEDS_ATTENTION` twice. The steps are the same as the pipeline's, but you run each
one yourself and add your own gate between them.

## 1. Implement

```bash
scripts/agent_run.sh task --cd <repo> --brief <brief.md> --name task-1 --effort medium \
  --run-dir <run-root>/task-1
```

The output has `thread_id` (keep it), token usage, the agent's JSON report (`status`,
`summary`, `files_changed`, `verification`, `concerns`, `questions`) and `git status`.
Handle NEEDS_CONTEXT / BLOCKED as in SKILL.md §4.

## 2. Gate 1: your own verification

The agent's `verification` field is a claim, not evidence.

1. Read the actual diff: `git diff -- <files>` plus the full contents of new untracked
   files. Compare it to `files_changed`. Unlisted changes and out-of-scope edits are
   findings.
2. Check each acceptance criterion against the code. Treat missing requirements and
   unrequested behaviour (extra flags, refactors, new dependencies) as findings.
3. Run the verification commands yourself, then probe at least one edge case from
   the brief that the agent's tests don't cover.
4. If gate 1 fails, go straight to a fix round. Reviewing code that's about to change
   wastes the review.

## 3. Gate 2: independent review

```bash
scripts/agent_run.sh review --cd <repo> --uncommitted --brief <review-brief.md> \
  --name task-1-review --effort high --run-dir <run-root>/task-1-review
```

The template is in `references/review-brief.md`. Triage every finding against the code
yourself. Confirmed critical or important findings go into the fix round. Fix minor
ones only if cheap, otherwise report them.

## 4. Fix rounds

```bash
scripts/agent_run.sh resume --cd <repo> --thread <thread_id> --brief <fix.md> \
  --name task-1-fix1 --run-dir <run-root>/task-1-fix1
```

Give a numbered list of specific problems (template in `references/implementer-brief.md`),
then re-run gate 1, and gate 2 too if the fix was substantial. Cap it at two rounds.
After that, change the brief, the effort or the task size, or make the fix yourself
if it's small and you understand it fully.

## 5. Accept

Commit (if authorized) or stage the task's files, and mark the task done.
