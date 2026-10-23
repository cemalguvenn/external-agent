# Quality review brief (for `agent_run.sh review --brief`)

With a brief, the script runs a fresh **read-only** review session (Codex: its read-only
sandbox; agy: a disposable copy with the diff pasted in). It tells that session
how to see the diff (from `--uncommitted` / `--base` / `--commit`) and enforces
`review.schema.json` on the answer: `verdict`, `summary`, `findings[]` with `severity`,
`location`, `problem`, `fix`. The brief supplies what the reviewer can't know: what the
change is for and what to focus on. Fill the `[...]`.

(Codex only: without `--brief`, the script runs Codex's built-in `codex exec review`, which returns
free text. That reviewer accepts no custom instructions together with a target, so it
can't be pointed at specific files or acceptance criteria. Use it only for a quick
general pass.)

```markdown
This change implements: [one-paragraph summary of the task and its acceptance criteria].

Review only these files: [paths from the implementer's files_changed].
Other uncommitted changes in the tree belong to earlier, already-accepted work; ignore them.

Focus on, in order:
1. Correctness bugs and unhandled edge cases (inputs, errors, boundaries, concurrency)
2. Tests that don't actually test the behaviour (tautologies, over-mocking, missing cases)
3. Divergence from the codebase's existing patterns
4. Maintainability problems that will bite soon (not style nitpicks)

Edge cases the spec requires (check each one is actually handled and tested):
[list them]

Only report problems you can point to in the code. If there are none, return APPROVE
with an empty findings list — do not invent findings to fill space.
```

## Triage rules for the controller

Codex review output is a second opinion, not a verdict. For each finding:

- **Check it against the code yourself** before acting. Reviewers (any model) produce
  plausible-sounding false positives; a finding you haven't confirmed is not a fix
  request.
- **critical / important + confirmed** → goes into the fix-round brief.
- **minor** → fix only if it's cheap and clearly right; otherwise note it in the final
  report.
- **Contradicts the spec or the user's instructions** → the spec wins; drop it.
- **Out of scope for this task** → don't fix now; list it under follow-ups.
