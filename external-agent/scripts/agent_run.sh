#!/usr/bin/env bash
# agent_run.sh — run an external coding agent CLI as a sub-agent and print a compact,
# parseable summary. Backends: codex (OpenAI Codex CLI) and agy (Google Antigravity CLI).
#
# Pipeline (the default way to delegate):
#   agent_run.sh delegate --cd DIR --brief FILE [--verify CMD] [--agent codex|agy] [--model M]
#                         [--review-agent codex|agy] [--review-model M] [--name NAME]
#                         [--effort LEVEL] [--review-effort LEVEL] [--max-fix-rounds N]
#                         [--no-review] [--sandbox workspace-write|read-only] [--network] [--run-dir DIR]
#     implement -> verify (run here, not trusted from the agent) -> fresh read-only review
#     -> send critical/important findings and verify failures back to the same thread
#     -> repeat up to N fix rounds -> one FINAL status line.
#
# Single steps (manual control):
#   agent_run.sh task   --cd DIR --brief FILE [--agent A] [--model M] [--effort E] [--sandbox MODE] ...
#   agent_run.sh resume --cd DIR --thread ID --brief FILE [--agent A] [--model M] ...
#   agent_run.sh review --cd DIR (--uncommitted | --base BRANCH | --commit SHA) [--brief FILE]
#                       [--agent A] [--model M] ...
#   agent_run.sh models --agent codex|agy          # list the models the account can use
#
# Everything an agent emits stays in the run directory; stdout gets only a short summary.
#
# Env: EXTERNAL_AGENT_MODEL (codex default model, default gpt-6.1-sol),
#      EXTERNAL_AGENT_AGY_MODEL (agy default model; no built-in default — ask the user),
#      EXTERNAL_AGENT_RUNS (run root).
# Both CLIs must be called with Claude Code's Bash sandbox disabled: inside it Codex is
# killed (exit 137) and agy cannot reach its own sandbox and credentials.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMPL_SCHEMA="$SCRIPT_DIR/implementer.schema.json"
REVIEW_SCHEMA="$SCRIPT_DIR/review.schema.json"

die() { echo "error: $*" >&2; exit 2; }

# Windows (Git Bash) usually has `python`, and `python3` may be the Microsoft Store stub
# that only prints an install hint, so probe for a Python that actually runs.
PY_BIN=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
    PY_BIN="$c"; break
  fi
done
[ -n "$PY_BIN" ] || die "Python 3.8+ not found (tried python3, python)"
# On Windows Python's stdout to a pipe uses the ANSI code page (e.g. cp1254), which
# cannot encode much of what agents write; bash reads it as UTF-8 anyway.
py_run() { PYTHONIOENCODING=utf-8 "$PY_BIN" "$@"; }

[ $# -ge 1 ] || die "usage: agent_run.sh delegate|task|resume|review|models [options]"
MODE="$1"; shift
case "$MODE" in delegate|task|resume|review|models) ;; *) die "unknown mode '$MODE'";; esac

CD="" BRIEF="" NAME="" THREAD="" RUN_DIR="" VERIFY=""
AGENT="codex" MODEL="" REVIEW_AGENT="" REVIEW_MODEL=""
EFFORT="medium" REVIEW_EFFORT="high"
SANDBOX="workspace-write" NETWORK=0 REVIEW_TARGET=() MAX_FIX=2 DO_REVIEW=1

while [ $# -gt 0 ]; do
  case "$1" in
    --cd) CD="$2"; shift 2;;
    --brief) BRIEF="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --thread) THREAD="$2"; shift 2;;
    --agent) AGENT="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --review-agent) REVIEW_AGENT="$2"; shift 2;;
    --review-model) REVIEW_MODEL="$2"; shift 2;;
    --effort) EFFORT="$2"; shift 2;;
    --review-effort) REVIEW_EFFORT="$2"; shift 2;;
    --sandbox) SANDBOX="$2"; shift 2;;
    --network) NETWORK=1; shift;;
    --run-dir) RUN_DIR="$2"; shift 2;;
    --verify) VERIFY="$2"; shift 2;;
    --max-fix-rounds) MAX_FIX="$2"; shift 2;;
    --no-review) DO_REVIEW=0; shift;;
    --uncommitted) REVIEW_TARGET=(--uncommitted); shift;;
    --base) REVIEW_TARGET=(--base "$2"); shift 2;;
    --commit) REVIEW_TARGET=(--commit "$2"); shift 2;;
    *) die "unknown option '$1'";;
  esac
done

# ---- backend selection ----------------------------------------------------------------

need_cli() {  # agent
  case "$1" in
    codex) command -v codex >/dev/null 2>&1 || die "codex not found on PATH (macOS/Homebrew: brew reinstall --cask codex)";;
    agy)   command -v agy >/dev/null 2>&1 || die "agy (Antigravity CLI) not found on PATH";;
    *)     die "unknown agent '$1' (codex|agy)";;
  esac
}

default_model() {  # agent -> prints model or nothing
  case "$1" in
    codex) printf '%s' "${EXTERNAL_AGENT_MODEL:-gpt-6.1-sol}";;
    agy)   printf '%s' "${EXTERNAL_AGENT_AGY_MODEL:-}";;
  esac
}

if [ "$MODE" = "models" ]; then
  need_cli "$AGENT"
  case "$AGENT" in
    agy)   agy models 2>/dev/null | grep -v '^Fetching';;
    codex) py_run - <<'PY'
import json, os
p = os.path.join(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"), "models_cache.json")
try:
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
except (OSError, ValueError):
    raise SystemExit("no ~/.codex/models_cache.json yet (run codex once)")
for m in d.get("models", d):
    lv = [x.get("effort") for x in m.get("supported_reasoning_levels", []) if isinstance(x, dict)]
    print(f"{m.get('slug')}\t{m.get('display_name', '')}\tefforts: {','.join(lv)}")
PY
    ;;
  esac
  exit 0
fi

need_cli "$AGENT"
[ -n "$MODEL" ] || MODEL="$(default_model "$AGENT")"
[ -n "$REVIEW_AGENT" ] || REVIEW_AGENT="$AGENT"
need_cli "$REVIEW_AGENT"
if [ -z "$REVIEW_MODEL" ]; then
  if [ "$REVIEW_AGENT" = "$AGENT" ]; then REVIEW_MODEL="$MODEL"; else REVIEW_MODEL="$(default_model "$REVIEW_AGENT")"; fi
fi
for pair in "$AGENT:$MODEL" "$REVIEW_AGENT:$REVIEW_MODEL"; do
  if [ "${pair%%:*}" = "agy" ] && [ -z "${pair#*:}" ]; then
    echo "error: agy needs a model and none was chosen. Ask the user to pick one of:" >&2
    agy models 2>/dev/null | grep -v '^Fetching' >&2
    echo "then pass --model (or --review-model) or set EXTERNAL_AGENT_AGY_MODEL." >&2
    exit 2
  fi
done

[ -n "$CD" ] && [ -d "$CD" ] || die "--cd must be an existing directory"
CD="$(cd "$CD" && pwd)"
case "$MODE" in
  delegate|task) [ -f "$BRIEF" ] || die "--brief FILE is required";;
  resume) [ -f "$BRIEF" ] || die "--brief FILE is required"; [ -n "$THREAD" ] || die "--thread ID is required";;
  review) [ ${#REVIEW_TARGET[@]} -gt 0 ] || die "review needs --uncommitted, --base BRANCH or --commit SHA";;
esac
for e in "$EFFORT" "$REVIEW_EFFORT"; do
  case "$e" in low|medium|high|xhigh|max) ;; *) die "effort must be low|medium|high|xhigh|max";; esac
done
if [ "$AGENT" = "agy" ] || [ "$REVIEW_AGENT" = "agy" ]; then
  case "$CD/" in "$HOME/Library/Application Support/"*)
    die "agy's terminal sandbox cannot read under ~/Library/Application Support; use a project folder elsewhere";;
  esac
fi
[ "$SANDBOX" = "read-only" ] && DO_REVIEW=0   # nothing to review when nothing can change

[ -n "$NAME" ] || NAME="$MODE"
SLUG="$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9._-' '-' | cut -c1-40)"
if [ -z "$RUN_DIR" ]; then
  ROOT="${EXTERNAL_AGENT_RUNS:-${TMPDIR:-/tmp}/external-agent}"
  RUN_DIR="$ROOT/$(basename "$CD")/$(date +%Y%m%d-%H%M%S)-$MODE-$SLUG"
fi
mkdir -p "$RUN_DIR" || die "cannot create run dir $RUN_DIR"
# Git Bash paths like /tmp/... mean nothing to Windows tools (Claude's Read included);
# C:/Users/... works in both.
command -v cygpath >/dev/null 2>&1 && RUN_DIR="$(cygpath -m "$RUN_DIR")"

IS_GIT=0 BASE_SHA=""
if git -C "$CD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=1
  BASE_SHA="$(git -C "$CD" rev-parse HEAD 2>/dev/null || true)"
  git -C "$CD" status --porcelain > "$RUN_DIR/git-status-before.txt" 2>/dev/null
fi

# ---- Python helpers -------------------------------------------------------------------
# One place for all JSON handling so the bash stays readable.
py() { py_run - "$@" <<'PY'
import json, shutil, sys
cmd, args = sys.argv[1], sys.argv[2:]

def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None

def last_json_object(text):
    """agy puts the structured answer in `response`, sometimes after prose."""
    dec = json.JSONDecoder()
    for i in range(len(text) - 1, -1, -1):
        if text[i] == "{":
            try:
                obj, end = dec.raw_decode(text[i:])
            except ValueError:
                continue
            if isinstance(obj, dict) and not text[i + end:].strip():
                return obj
    return None

if cmd == "snapshot":          # copy a project without VCS/dependency dirs (no rsync on Git Bash)
    shutil.copytree(args[0], args[1], symlinks=True, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".git", "node_modules", ".venv", "venv", "target",
                                                  "dist", "build", ".next", "__pycache__"))

elif cmd == "meta":            # stage dir -> thread/tokens/errors as shell assignments
    d = args[0]
    thread, tin, tcached, tout, errors = "", 0, 0, 0, 0
    agy = load(f"{d}/agy.json")
    if agy is not None:
        u = agy.get("usage") or {}
        thread = agy.get("conversation_id", "")
        tin, tcached, tout = u.get("input_tokens", 0), u.get("cache_read_tokens", 0), u.get("output_tokens", 0)
        errors = 0 if agy.get("status") == "SUCCESS" else 1
    else:
        try:
            for line in open(f"{d}/events.jsonl", encoding="utf-8", errors="replace"):
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                t = e.get("type")
                if t == "thread.started":
                    thread = e.get("thread_id", "")
                elif t == "turn.completed":
                    u = e.get("usage") or {}
                    tin, tcached, tout = u.get("input_tokens", 0), u.get("cached_input_tokens", 0), u.get("output_tokens", 0)
                elif t in ("turn.failed", "error"):
                    errors += 1
        except OSError:
            pass
    print(f"EV_THREAD='{thread}' EV_IN={tin} EV_CACHED={tcached} EV_OUT={tout} EV_ERR={errors}")

elif cmd == "agy-extract":     # agy.json -> report file (structured answer), exit 1 if none
    agy = load(args[0]) or {}
    # A transient API error late in the turn can mark the run ERROR even though the
    # schema-checked answer arrived, so structured_output counts whatever the status.
    obj = agy.get("structured_output")
    if not isinstance(obj, dict):
        obj = last_json_object(agy.get("response") or "") if agy.get("status") == "SUCCESS" else None
    if obj is None:
        sys.exit(1)
    with open(args[1], "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)

elif cmd == "field":           # report.json field (lists joined with ', ')
    d = load(args[0]) or {}
    v = d.get(args[1], "")
    print(", ".join(map(str, v)) if isinstance(v, list) else v)

elif cmd == "review-counts":   # review.json -> verdict + counts
    d = load(args[0]) or {}
    f = d.get("findings", [])
    n = {s: sum(1 for x in f if x.get("severity") == s) for s in ("critical", "important", "minor")}
    print(f"RV_VERDICT='{d.get('verdict', 'NONE')}' RV_CRIT={n['critical']} RV_IMP={n['important']} RV_MINOR={n['minor']}")

elif cmd == "review-brief":    # task brief + files -> review brief
    brief, files = open(args[0], encoding="utf-8").read(), args[1]
    print("The change below was made to implement this task brief:\n\n<task-brief>\n"
          f"{brief}\n</task-brief>\n\n"
          f"Review only these files: {files or '(see git status)'}.\n"
          "Other uncommitted changes belong to earlier, already-accepted work; ignore them.\n\n"
          "Focus on, in order:\n"
          "1. Requirements or acceptance criteria from the brief that are missing or wrong\n"
          "2. Correctness bugs and unhandled edge cases (inputs, errors, boundaries, float/precision)\n"
          "3. Tests that don't actually test the behaviour\n"
          "4. Divergence from the codebase's existing patterns\n"
          "Ignore style nitpicks. Only report problems you can point to in the code. If there are\n"
          "none, return APPROVE with an empty findings list.")

elif cmd == "fix-brief":       # review.json + verify log -> numbered fix list
    review, vlog, vcmd = load(args[0]) if args[0] else None, args[1], args[2]
    items = []
    for x in (review or {}).get("findings", []):
        if x.get("severity") in ("critical", "important"):
            items.append(f"[{x['severity']}] {x.get('location', '')}: {x.get('problem', '')} "
                         f"Suggested fix: {x.get('fix', '')}")
    if vlog:
        tail = open(vlog, encoding="utf-8", errors="replace").read().splitlines()[-40:]
        items.append(f"Verification command `{vcmd}` fails when run independently. Output tail:\n"
                     + "\n".join("    " + l for l in tail))
    print("An independent review of your work found these problems. Fix all of them, nothing else.\n"
          "If you are confident a finding is wrong, do not change code for it: explain why in "
          "`concerns`.\n")
    for i, it in enumerate(items, 1):
        print(f"{i}. {it}")
    print("\nThen re-run your verification. Same rules as before: stay in scope, no git commits. "
          "Report with the same JSON schema.")

elif cmd == "minor":           # review.json -> minor findings, one per line
    d = load(args[0]) or {}
    for x in d.get("findings", []):
        if x.get("severity") == "minor":
            print(f"  - {x.get('location', '')}: {x.get('problem', '')}")
PY
}

# ---- backends: each step writes into its stage dir and sets RC -------------------------
# Implementer steps write report.json; review steps write review.json (or review.md).

codex_common() {  # model effort
  COMMON=(-m "$1" -c "model_reasoning_effort=\"$2\"")
  [ $NETWORK -eq 1 ] && COMMON+=(-c "sandbox_workspace_write.network_access=true")
}

# Appended to every agy prompt. Without the schema spelled out, a Flash model went
# looking for "the schema" outside the project (env vars, /tmp, other tools' folders)
# for minutes after it already had the answer.
agy_footer() {  # schema_file
  printf '\n\n---\nRules for this run: work only inside the current directory. Do not inspect files outside it, environment variables, or other tools'"'"' data. Nothing else needs to be found: everything you need is in this prompt and the project.\nWhen done, your final message must be only a JSON object matching this schema (it is also enforced):\n'
  cat "$1"
}

# Windows caps a whole command line at 32,767 characters (Git Bash fails with "Argument
# list too long"), and a review prompt with the diff pasted in can be far longer. Such a
# prompt stays in its file, and agy is pointed at it instead.
agy_prompt_args() {  # prompt_file -> PROMPT_ARGS
  local f="$1" d p
  if [ "$(wc -c < "$f")" -lt 24000 ]; then PROMPT_ARGS=(-p "$(cat "$f")"); return; fi
  d="$(dirname "$f")"; p="$f"
  if command -v cygpath >/dev/null 2>&1; then d="$(cygpath -w "$d")"; p="$(cygpath -w "$f")"; fi
  PROMPT_ARGS=(-p "Your complete instructions are in the file $p. Read that whole file first, then follow it exactly. It is the one file outside the current directory you may read." --add-dir "$d")
}

agy_common() {  # model effort
  COMMON=(--model "$1" --print-timeout 30m --output-format json)
  # Model ids like gemini-3.8-flash-medium already carry their effort level.
  case "$1" in *-low|*-medium|*-high|*-xhigh|*-max) ;; *) COMMON+=(--effort "$2");; esac
}

how_to_see_change() {  # review target... -> sentence for the reviewer prompt
  case "$1" in
    --uncommitted) echo '`git status --short`, then `git diff HEAD` for tracked files, and read untracked files in full';;
    --base)        echo "\`git diff $2...HEAD\` (plus \`git status --short\` for uncommitted work)";;
    --commit)      echo "\`git show $2\`";;
  esac
}

inline_change() {  # review target... -> the change itself, for reviewers that can't run git
  ( cd "$CD" || exit 1
    case "$1" in
      --uncommitted)
        echo '$ git status --short'; git status --short
        echo; echo '$ git diff HEAD'; git diff HEAD
        git ls-files --others --exclude-standard | while IFS= read -r f; do
          echo; echo "=== new file: $f ==="; head -c 60000 "$f"
        done;;
      --base)   git diff "$2...HEAD"; echo; git status --short;;
      --commit) git show "$2";;
    esac ) | head -c 400000
}

# agy has no enforced read-only mode: headless runs without a permission bypass end the
# turn with no answer as soon as the model tries any command. So agy's read-only work
# (reviews, investigations) runs with full permissions in a throwaway copy of the
# project. It can run code there, and nothing it does reaches the real tree.
make_snapshot() {  # -> SNAP
  # Under $HOME, not $TMPDIR: agy's terminal sandbox restricts commands outside its
  # trusted workspaces, and a copy in /var/folders made a trivial run take minutes.
  local root="${EXTERNAL_AGENT_SNAP_ROOT:-$HOME/.cache/external-agent}"
  mkdir -p "$root" || die "cannot create $root"
  SNAP="$(mktemp -d "$root/external-agent-snap.XXXXXX")" || die "cannot create snapshot dir"
  py snapshot "$CD" "$SNAP" || die "cannot copy the project into $SNAP"
}
drop_snapshot() {
  case "${SNAP:-}" in */external-agent-snap.??????) rm -rf "$SNAP";; esac
  SNAP=""
}

backend_task() {  # agent model stage_dir brief effort
  local agent="$1" model="$2" dir="$3" brief="$4" effort="$5"
  case "$agent" in
    codex)
      codex_common "$model" "$effort"
      codex exec "${COMMON[@]}" -s "$SANDBOX" -C "$CD" --skip-git-repo-check \
        --output-schema "$IMPL_SCHEMA" -o "$dir/report.json" --json - \
        < "$brief" > "$dir/events.jsonl" 2> "$dir/stderr.log"
      RC=$?;;
    agy)
      agy_common "$model" "$effort"
      local where="$CD"
      { cat "$brief"
        if [ "$SANDBOX" = "read-only" ]; then
          printf '\n\nYou are working in a disposable copy of the project: you may run code to investigate, but report findings only; any edits are discarded.'
        fi
        agy_footer "$IMPL_SCHEMA"
      } > "$dir/agy-prompt.md"
      if [ "$SANDBOX" = "read-only" ]; then make_snapshot; where="$SNAP"; fi
      agy_prompt_args "$dir/agy-prompt.md"
      ( cd "$where" && agy "${PROMPT_ARGS[@]}" \
          "${COMMON[@]}" --dangerously-skip-permissions --sandbox --json-schema "$IMPL_SCHEMA" ) \
        > "$dir/agy.json" 2> "$dir/stderr.log"
      RC=$?
      drop_snapshot
      py agy-extract "$dir/agy.json" "$dir/report.json" || { [ $RC -eq 0 ] && RC=3; };;
  esac
}

backend_resume() {  # agent model stage_dir thread brief effort
  local agent="$1" model="$2" dir="$3" thread="$4" brief="$5" effort="$6"
  case "$agent" in
    codex)
      codex_common "$model" "$effort"
      # `exec resume` has no -C: it must run from the project directory.
      ( cd "$CD" && codex exec resume "$thread" "${COMMON[@]}" -c "sandbox_mode=\"$SANDBOX\"" \
          --skip-git-repo-check --output-schema "$IMPL_SCHEMA" -o "$dir/report.json" --json - \
          < "$brief" > "$dir/events.jsonl" 2> "$dir/stderr.log" )
      RC=$?;;
    agy)
      agy_common "$model" "$effort"
      { cat "$brief"; agy_footer "$IMPL_SCHEMA"; } > "$dir/agy-prompt.md"
      agy_prompt_args "$dir/agy-prompt.md"
      ( cd "$CD" && agy "${PROMPT_ARGS[@]}" --conversation "$thread" \
          "${COMMON[@]}" --dangerously-skip-permissions --sandbox --json-schema "$IMPL_SCHEMA" ) \
        > "$dir/agy.json" 2> "$dir/stderr.log"
      RC=$?
      py agy-extract "$dir/agy.json" "$dir/report.json" || { [ $RC -eq 0 ] && RC=3; };;
  esac
}

backend_review() {  # agent model stage_dir brief-or-empty effort target...
  local agent="$1" model="$2" dir="$3" brief="$4" effort="$5"; shift 5
  if [ -z "$brief" ]; then
    [ "$agent" = "codex" ] || { brief="$dir/default-review-brief.md"
      echo "Review this change for correctness bugs, unhandled edge cases and weak tests." > "$brief"; }
  fi
  if [ "$agent" = "codex" ] && [ -z "$brief" ]; then
    # Built-in reviewer. `codex exec review` refuses custom instructions together
    # with a target (--uncommitted/--base/--commit), so it runs without a brief.
    codex_common "$model" "$effort"
    ( cd "$CD" && codex exec review "$@" "${COMMON[@]}" \
        -o "$dir/review.md" < /dev/null > "$dir/events.log" 2> "$dir/stderr.log" )
    RC=$?; return
  fi
  case "$agent" in
    codex)
      # Fresh read-only session (it never saw the implementer's reasoning).
      { printf 'You are a code reviewer. Do not modify any files.\nInspect the change with %s. Read surrounding code as needed to judge it.\n\n' "$(how_to_see_change "$@")"
        cat "$brief"
        printf '\n\nFinal message: JSON matching the schema (verdict, summary, findings).\n'
      } > "$dir/review-prompt.md"
      codex_common "$model" "$effort"
      codex exec "${COMMON[@]}" -s read-only -C "$CD" --skip-git-repo-check \
        --output-schema "$REVIEW_SCHEMA" -o "$dir/review.json" --json - \
        < "$dir/review-prompt.md" > "$dir/events.jsonl" 2> "$dir/stderr.log"
      RC=$?;;
    agy)
      # The copy has no .git, so the change itself is pasted into the prompt.
      { printf 'You are a code reviewer working in a disposable copy of the project (no git history).\nYou may read files and run code or tests to check behaviour; do not try to fix anything, edits are discarded.\nThe change under review:\n\n<change>\n'
        inline_change "$@"
        printf '\n</change>\n\n'
        cat "$brief"
        agy_footer "$REVIEW_SCHEMA"
      } > "$dir/review-prompt.md"
      agy_common "$model" "$effort"
      make_snapshot
      agy_prompt_args "$dir/review-prompt.md"
      ( cd "$SNAP" && agy "${PROMPT_ARGS[@]}" "${COMMON[@]}" \
          --dangerously-skip-permissions --sandbox --json-schema "$REVIEW_SCHEMA" ) \
        > "$dir/agy.json" 2> "$dir/stderr.log"
      RC=$?
      drop_snapshot
      py agy-extract "$dir/agy.json" "$dir/review.json" || { [ $RC -eq 0 ] && RC=3; };;
  esac
}

TOT_IN=0 TOT_CACHED=0 TOT_OUT=0
add_tokens() {  # stage_dir -> sets EV_* and accumulates totals
  eval "$(py meta "$1")"
  TOT_IN=$((TOT_IN + EV_IN)); TOT_CACHED=$((TOT_CACHED + EV_CACHED)); TOT_OUT=$((TOT_OUT + EV_OUT))
}
ktok() { awk -v n="$1" 'BEGIN { if (n >= 1000) printf "%.0fk", n/1000; else print n }'; }

git_tail() {
  [ $IS_GIT -eq 1 ] || return 0
  echo "git: $(git -C "$CD" status --short 2>/dev/null | head -n 20 | tr '\n' ';' | sed 's/;$//')"
  local now; now="$(git -C "$CD" rev-parse HEAD 2>/dev/null || true)"
  if [ -n "$BASE_SHA" ] && [ "$now" != "$BASE_SHA" ]; then
    echo "WARNING: HEAD moved $BASE_SHA -> $now (the agent committed or switched branch)"
  fi
}

# ---- delegate: the pipeline -----------------------------------------------------------

if [ "$MODE" = "delegate" ]; then
  START=$(date +%s); N=0
  cp "$BRIEF" "$RUN_DIR/brief.md"
  stage() { N=$((N + 1)); STAGE_DIR="$RUN_DIR/$(printf '%02d' $N)-$1"; mkdir -p "$STAGE_DIR"; }
  line() { printf 'stage %-11s %-18s %s\n' "$1" "$2" "$3"; }
  echo "agents: implement=$AGENT/$MODEL review=$REVIEW_AGENT/$REVIEW_MODEL"

  finish() {  # final_status [detail]
    {
      echo "FINAL $1"
      [ -n "${2:-}" ] && echo "$2"
      echo "thread_id=$THREAD_ID"
      echo "files: ${FILES:-(none)}"
      [ -n "${CONCERNS:-}" ] && echo "concerns: $CONCERNS"
      [ -n "${MINOR:-}" ] && { echo "minor findings (not fixed):"; echo "$MINOR"; }
      echo "agent_tokens: in=$(ktok $TOT_IN) (cached $(ktok $TOT_CACHED)) out=$(ktok $TOT_OUT)"
      echo "elapsed_seconds=$(( $(date +%s) - START ))"
      echo "run_dir=$RUN_DIR"
      git_tail
    } | tee "$RUN_DIR/summary.txt"
    exit 0
  }

  read_report() {  # stage_dir -> STATUS FILES CONCERNS QUESTIONS SUMMARY
    STATUS="$(py field "$1/report.json" status)"
    FILES="$(py field "$1/report.json" files_changed)"
    CONCERNS="$(py field "$1/report.json" concerns)"
    QUESTIONS="$(py field "$1/report.json" questions)"
    SUMMARY="$(py field "$1/report.json" summary)"
  }

  # 1. implement
  stage implement
  backend_task "$AGENT" "$MODEL" "$STAGE_DIR" "$RUN_DIR/brief.md" "$EFFORT"
  add_tokens "$STAGE_DIR"; THREAD_ID="$EV_THREAD"
  if [ $RC -ne 0 ] || [ ! -s "$STAGE_DIR/report.json" ]; then
    line implement FAILED "exit=$RC"
    finish FAILED "agent error, see $STAGE_DIR/stderr.log: $(tail -n 3 "$STAGE_DIR/stderr.log" | tr '\n' ' ')"
  fi
  read_report "$STAGE_DIR"
  line implement "$STATUS" "in=$(ktok $EV_IN) out=$(ktok $EV_OUT)"
  case "$STATUS" in
    NEEDS_CONTEXT|BLOCKED) finish "$STATUS" "summary: $SUMMARY
questions: ${QUESTIONS:-(none)}";;
  esac
  [ "$SANDBOX" = "read-only" ] && finish "$STATUS" "answer: $SUMMARY"

  ROUND=0
  while :; do
    # 2. verify — run here, independent of what the agent says it ran
    VLOG=""
    if [ -n "$VERIFY" ]; then
      stage verify
      ( cd "$CD" && bash -c "$VERIFY" ) > "$STAGE_DIR/verify.log" 2>&1
      VRC=$?
      VSHOW="$(printf '%s' "$VERIFY" | cut -c1-70)"
      if [ $VRC -eq 0 ]; then line verify PASS "$VSHOW"
      else line verify FAIL "$VSHOW (log: $STAGE_DIR/verify.log)"; VLOG="$STAGE_DIR/verify.log"; fi
    fi

    # 3. review — fresh read-only session, possibly a different agent
    RJSON="" RV_VERDICT=SKIPPED RV_CRIT=0 RV_IMP=0 RV_MINOR=0
    if [ $DO_REVIEW -eq 1 ] && [ -z "$VLOG" ]; then
      stage review
      py review-brief "$RUN_DIR/brief.md" "$FILES" > "$STAGE_DIR/review-brief.md"
      backend_review "$REVIEW_AGENT" "$REVIEW_MODEL" "$STAGE_DIR" "$STAGE_DIR/review-brief.md" "$REVIEW_EFFORT" --uncommitted
      add_tokens "$STAGE_DIR"
      if [ -s "$STAGE_DIR/review.json" ]; then
        RJSON="$STAGE_DIR/review.json"; eval "$(py review-counts "$RJSON")"
        line review "$RV_VERDICT" "critical=$RV_CRIT important=$RV_IMP minor=$RV_MINOR"
      else
        line review FAILED "exit=$RC (continuing without review)"
        CONCERNS="${CONCERNS:+$CONCERNS; }independent review failed (exit=$RC, see $STAGE_DIR/stderr.log)"
      fi
    fi
    MINOR="$( [ -n "$RJSON" ] && py minor "$RJSON" )"

    BLOCKING=$((RV_CRIT + RV_IMP))
    if [ -z "$VLOG" ] && [ $BLOCKING -eq 0 ]; then
      if [ -n "$CONCERNS" ] || [ "$STATUS" = "DONE_WITH_CONCERNS" ]; then finish DONE_WITH_CONCERNS
      else finish DONE; fi
    fi
    if [ $ROUND -ge "$MAX_FIX" ]; then
      finish NEEDS_ATTENTION "unresolved after $ROUND fix round(s): $( [ -n "$VLOG" ] && echo "verify failing ($VLOG)"; [ $BLOCKING -gt 0 ] && echo "$BLOCKING blocking finding(s) in $RJSON")"
    fi

    # 4. fix round on the implementer's own thread
    ROUND=$((ROUND + 1))
    stage "fix-$ROUND"
    py fix-brief "$RJSON" "$VLOG" "$VERIFY" > "$STAGE_DIR/fix-brief.md"
    backend_resume "$AGENT" "$MODEL" "$STAGE_DIR" "$THREAD_ID" "$STAGE_DIR/fix-brief.md" "$EFFORT"
    add_tokens "$STAGE_DIR"
    if [ $RC -ne 0 ] || [ ! -s "$STAGE_DIR/report.json" ]; then
      line "fix-$ROUND" FAILED "exit=$RC"
      finish FAILED "agent error during fix round, see $STAGE_DIR/stderr.log"
    fi
    read_report "$STAGE_DIR"
    line "fix-$ROUND" "$STATUS" "in=$(ktok $EV_IN) out=$(ktok $EV_OUT)"
    case "$STATUS" in
      NEEDS_CONTEXT|BLOCKED) finish "$STATUS" "summary: $SUMMARY
questions: ${QUESTIONS:-(none)}";;
    esac
  done
fi

# ---- single steps ---------------------------------------------------------------------

[ -n "$BRIEF" ] && cp "$BRIEF" "$RUN_DIR/brief.md"
START=$(date +%s)
case "$MODE" in
  task)   backend_task "$AGENT" "$MODEL" "$RUN_DIR" "$RUN_DIR/brief.md" "$EFFORT";;
  resume) backend_resume "$AGENT" "$MODEL" "$RUN_DIR" "$THREAD" "$RUN_DIR/brief.md" "$EFFORT";;
  review) backend_review "$AGENT" "$MODEL" "$RUN_DIR" "${BRIEF:+$RUN_DIR/brief.md}" "$EFFORT" "${REVIEW_TARGET[@]}";;
esac

echo "mode=$MODE agent=$AGENT"
echo "exit_code=$RC"
echo "elapsed_seconds=$(( $(date +%s) - START ))"
echo "model=$MODEL effort=$EFFORT"
echo "run_dir=$RUN_DIR"
[ -n "$BASE_SHA" ] && echo "base_sha=$BASE_SHA"
if [ -f "$RUN_DIR/events.jsonl" ] || [ -f "$RUN_DIR/agy.json" ]; then
  add_tokens "$RUN_DIR"
  echo "thread_id=${EV_THREAD:-UNKNOWN}"
  echo "tokens_in=$EV_IN tokens_cached=$EV_CACHED tokens_out=$EV_OUT"
fi

OUT=""
for f in report.json review.json review.md; do
  [ -s "$RUN_DIR/$f" ] && { OUT="$RUN_DIR/$f"; break; }
done
if [ -n "$OUT" ]; then
  if [ "$MODE" = "review" ]; then echo "--- review (from $AGENT: triage before acting) ---"
  else echo "--- report (from $AGENT: claims, not verified) ---"; fi
  case "$OUT" in
    *.json) py_run -m json.tool "$OUT" 2>/dev/null || cat "$OUT";;
    *) cat "$OUT"; echo;;
  esac
else
  echo "status=NO_REPORT"
  echo "--- stderr tail ---"; tail -n 15 "$RUN_DIR/stderr.log" 2>/dev/null
  [ -f "$RUN_DIR/events.jsonl" ] && { echo "--- events tail ---"; tail -n 5 "$RUN_DIR/events.jsonl" | cut -c1-400; }
fi
git_tail
exit $RC
