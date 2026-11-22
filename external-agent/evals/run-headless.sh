#!/usr/bin/env bash
# Run this skill's eval cases with headless Claude Code, then grade them.
#
# Why not `claude plugin eval`: it runs each case in an OS sandbox with no network
# and a stand-in HOME, so Codex and agy can't reach their servers or credentials and
# never run (Claude then does the work itself and LLM judges may still pass it).
#
# usage: evals/run-headless.sh [case-name ...]     (default: every case)
# env:   CLAUDE_BIN  (default: claude, must be logged in; needs `claude -p`)
#        EVAL_MODEL  (default: claude-opus-5-5)   EVAL_ROOT (default: ~/.cache/external-agent/eval-runs/<date>)
# Workspaces sit under $HOME because agy only edits trusted folders. Paid runs.
set -u
EV="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
ROOT="${EVAL_ROOT:-$HOME/.cache/external-agent/eval-runs/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$ROOT"
[ $# -gt 0 ] && CASES=("$@") || CASES=($(cd "$EV" && for d in */; do [ -f "$d/prompt.md" ] && echo "${d%/}"; done))

run_case() {
  local c="$1" src="$EV/$1" w="$ROOT/$1" o="$ROOT/$1.out" prompt turns t0
  rm -rf "$w" "$o"; mkdir -p "$w" "$o"
  ( cd "$w" && bash "$src/place-files.sh" && git init -q && git add -A &&
    git -c user.email=eval@local -c user.name=eval commit -qm scaffold )
  prompt="$(awk 'f>=2{print} /^---$/{f++}' "$src/prompt.md" | sed '/./,$!d')"
  turns="$(awk '/^max_turns:/{print $2}' "$src/prompt.md")"
  t0=$(date +%s)
  # Drop variables a parent Claude Code session injects (its API proxy and session
  # ids): with them the child can't use its own login and fails with auth errors.
  local strip=(-u ANTHROPIC_BASE_URL -u CLAUDECODE)
  for v in $(env | awk -F= '/^CLAUDE_CODE_|^CLAUDE_AGENT_/{print $1}'); do strip+=(-u "$v"); done
  ( cd "$w" && env "${strip[@]}" "$CLAUDE_BIN" -p "$prompt" --model "${EVAL_MODEL:-claude-opus-5-5}" \
      --max-turns "${turns:-60}" --allowedTools Bash Read Write Edit Glob Grep Skill \
      --output-format stream-json --verbose > "$o/trace.jsonl" 2> "$o/stderr.log" )
  echo "exit=$? seconds=$(( $(date +%s) - t0 ))" > "$o/meta.txt"
}

for c in "${CASES[@]}"; do run_case "$c" & sleep 3; done
wait
python3 "$EV/grade.py" "$ROOT"
