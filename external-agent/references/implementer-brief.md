# Implementer brief template

Copy this into a file (e.g. `<run-root>/task-N-brief.md`), fill every `[...]`, delete
sections that don't apply, and pass it with `--brief`. Codex starts with **zero**
knowledge of this conversation, so the brief is the entire world it gets. Paste text in
rather than pointing at files it would have to discover, except for code it should read
in place.

With `delegate`, the same brief is also handed to the independent reviewer as the spec
to judge against. Edge cases you list here get checked twice; edge cases you leave out
may get checked by neither.

```markdown
# Task [N]: [short name]

## Goal
[One or two sentences: what must be true when this task is done, and why it matters.]

## Context
- Project: [what the codebase is, language/framework, how it's laid out]
- Where this fits: [the larger plan in a sentence; what earlier tasks already did]
- Relevant code to read first: [paths + what to look for in each]
- Conventions to follow: [naming, error handling, test style — point at an example file]

## Requirements
1. [Concrete, checkable requirement]
2. [...]

## Acceptance criteria
- [Observable behaviour, e.g. "`parse_duration('1h30m')` returns 5400"]
- [Edge cases that must be handled, e.g. "empty string raises ValueError"]
- [Tests that must exist / pass]

## Verify with
[Exact command, e.g. `python3 -m unittest discover -s tests -t .`. Pass the same
command to `delegate --verify` so it is also run outside Codex.]
Add tests for every acceptance criterion and edge case above to the suite this
command runs.

## Scope limits
- Only touch: [files/directories]. If you believe something else must change, stop and
  report NEEDS_CONTEXT or DONE_WITH_CONCERNS instead of changing it.
- Do NOT run `git commit`, `git push`, `git checkout`, `git reset` or change branches.
  The controller reviews and commits.
- Do not add dependencies unless listed here: [allowed deps or "none"].
- [Anything else off-limits: generated files, migrations, public API, etc.]

## Working rules
- Read the relevant code before editing; match the surrounding style.
- If the requirements are ambiguous or conflict with the code, do not guess: report
  NEEDS_CONTEXT with specific questions. Bad work is worse than no work.
- Run the verification commands yourself and report their real output.
- Before reporting, re-read your diff: anything missing from the requirements? anything
  added that wasn't asked for? Fix it first.

## Report
Your final message is a JSON object (schema enforced):
- status: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED
- summary, files_changed, verification (command + actual result), concerns, questions
```

## Fix-round brief (for `agent_run.sh resume`, manual mode)

`delegate` writes fix briefs itself. In manual mode, the resumed thread still remembers
the original task, so keep it short and specific:

```markdown
Review of your work found these problems. Fix all of them, nothing else.

1. [file:line or function] — [what is wrong] — [what correct looks like]
2. [...]

Then re-run: [verification commands]. Same rules as before (no commits, stay in scope).
Report with the same JSON schema.
```

## Answering NEEDS_CONTEXT

Resume the same thread with the answers, numbered to match the questions, plus "Now
continue the task." Do not start a fresh `task` run — the thread already has the
context it built up.
