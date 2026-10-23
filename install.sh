#!/usr/bin/env bash
# Install the external-agent skill into ~/.claude/skills/.
#   ./install.sh           copy
#   ./install.sh --link    symlink (updates arrive with `git pull`)
#   ./install.sh --force   replace an existing install
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)/external-agent"
DEST_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST="$DEST_DIR/external-agent"
LINK=0 FORCE=0
for a in "$@"; do
  case "$a" in
    --link) LINK=1;;
    --force) FORCE=1;;
    *) echo "usage: ./install.sh [--link] [--force]" >&2; exit 2;;
  esac
done

[ -f "$SRC/SKILL.md" ] || { echo "error: $SRC/SKILL.md not found" >&2; exit 1; }
mkdir -p "$DEST_DIR"
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  if [ $FORCE -eq 0 ]; then
    echo "error: $DEST already exists (use --force to replace it)" >&2; exit 1
  fi
  rm -rf "$DEST"
fi

if [ $LINK -eq 1 ]; then
  ln -s "$SRC" "$DEST"
  echo "linked $DEST -> $SRC"
else
  cp -R "$SRC" "$DEST"
  echo "copied to $DEST"
fi
chmod +x "$SRC/scripts/agent_run.sh" "$DEST/scripts/agent_run.sh" 2>/dev/null || true

for c in codex agy; do
  if command -v "$c" >/dev/null 2>&1; then echo "found $c"; else echo "note: $c not on PATH (install it to use that subcontractor)"; fi
done
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || echo "warning: Python 3 not found"
echo "Restart Claude Code to load the skill."
