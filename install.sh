#!/usr/bin/env bash
# Install the external-agent skill into Claude Code and/or Antigravity skills directories.
#   ./install.sh                         copy (installs to both if Antigravity is present, else Claude)
#   ./install.sh --link                  symlink (updates arrive with `git pull`)
#   ./install.sh --force                 replace an existing install
#   ./install.sh --target claude|agy|both
set -eu

SRC="$(cd "$(dirname "$0")" && pwd)/external-agent"
CLAUDE_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
AGY_DIR="${AGY_SKILLS_DIR:-$HOME/.gemini/config/skills}"
LINK=0 FORCE=0 TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --link) LINK=1; shift;;
    --force) FORCE=1; shift;;
    --target) TARGET="${2:-}"; shift 2;;
    *) echo "usage: ./install.sh [--link] [--force] [--target claude|agy|both]" >&2; exit 2;;
  esac
done

[ -f "$SRC/SKILL.md" ] || { echo "error: $SRC/SKILL.md not found" >&2; exit 1; }

if [ -z "$TARGET" ]; then
  if [ -d "$HOME/.gemini/config" ] || [ -d "$HOME/.gemini/antigravity" ] || command -v agy >/dev/null 2>&1; then
    TARGET="both"
  else
    TARGET="claude"
  fi
fi

install_one() {
  local dir="$1" dest="$1/external-agent"
  mkdir -p "$dir"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ $FORCE -eq 0 ]; then
      echo "error: $dest already exists (use --force to replace it)" >&2; exit 1
    fi
    rm -rf "$dest"
  fi
  if [ $LINK -eq 1 ]; then
    ln -s "$SRC" "$dest"
    echo "linked $dest -> $SRC"
  else
    cp -R "$SRC" "$dest"
    echo "copied to $dest"
  fi
  chmod +x "$SRC/scripts/agent_run.sh" "$dest/scripts/agent_run.sh" 2>/dev/null || true
}

case "$TARGET" in
  claude) install_one "$CLAUDE_DIR";;
  agy)    install_one "$AGY_DIR";;
  both)   install_one "$CLAUDE_DIR"; install_one "$AGY_DIR";;
  *)      echo "error: --target must be claude, agy, or both" >&2; exit 2;;
esac

for c in claude codex agy; do
  if command -v "$c" >/dev/null 2>&1; then echo "found $c"; else echo "note: $c not on PATH (install it to use that agent)"; fi
done
command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || echo "warning: Python 3 not found"
echo "Restart Claude Code / Antigravity to load the skill."
