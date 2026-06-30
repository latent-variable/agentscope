#!/usr/bin/env bash
# Wire every installed agent CLI to ~/.agents (canonical user scope). Idempotent.
# Only wires tools it actually finds installed; re-run anytime after adding a tool/skill.
# Usage: sync.sh [--check]
set -euo pipefail

AGENTS="$HOME/.agents"
CANON="$AGENTS/AGENTS.md"
SKILLS="$AGENTS/skills"
MEM="$AGENTS/memory"
BK="$AGENTS/backups/$(date +%Y%m%d-%H%M%S)"

# Claude stores per-scope memory under an encoded path = abs dir with '/' -> '-'.
# For user scope that dir is $HOME, so this resolves per-machine (no hardcoded username).
ENC="$(printf '%s' "$HOME" | tr '/' '-')"
CLAUDE_MEM="$HOME/.claude/projects/$ENC/memory"

note(){ printf '  %s\n' "$*"; }

# A tool counts as "installed" if its config dir exists.
have(){ [ -d "$1" ]; }

# link <target> <linkpath> : back up a real file/dir at linkpath, then symlink.
link(){
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then ln -sfn "$src" "$dst"; note "relink  $dst"; return; fi
  if [ -e "$dst" ]; then
    mkdir -p "$BK"
    mv "$dst" "$BK/$(echo "${dst#$HOME/}" | tr '/' '_')"
    note "backup  $dst"
  fi
  ln -s "$src" "$dst"; note "link    $dst -> $src"
}

# link_skills <skills_dir> : per-skill symlinks into a tool's skills dir.
# Prunes dead canon links first (a skill removed from canon leaves a dangling link),
# then (re)links every current canon skill. Real non-canon skills in the dir are left alone.
link_skills(){
  local dir="$1" l tgt
  mkdir -p "$dir"
  for l in "$dir"/*; do
    [ -L "$l" ] || continue
    tgt="$(readlink "$l")"
    case "$tgt" in "$SKILLS"/*) [ -e "$l" ] || { rm "$l"; note "prune   dead link $(basename "$l")"; };; esac
  done
  for s in "$SKILLS"/*/; do
    [ -d "$s" ] || continue
    link "${s%/}" "$dir/$(basename "$s")"
  done
}

if [ "${1:-}" = "--check" ]; then
  echo "== link check =="
  for p in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.gemini/GEMINI.md" \
           "$HOME/.gemini/AGENTS.md" "$HOME/.pi/agent/AGENTS.md" "$CLAUDE_MEM"; do
    if [ -L "$p" ]; then printf '  OK    %s -> %s\n' "$p" "$(readlink "$p")";
    elif [ -e "$p" ]; then printf '  REAL  %s (not a symlink)\n' "$p";
    else printf '  --    %s (absent)\n' "$p"; fi
  done
  exit 0
fi

echo "== wiring installed agents to $AGENTS =="

# --- Claude Code ---
if have "$HOME/.claude"; then
  link "$CANON" "$HOME/.claude/CLAUDE.md"
  link_skills "$HOME/.claude/skills"
  link "$MEM" "$CLAUDE_MEM"     # Claude auto-memory writes land in canon
else note "skip Claude (~/.claude absent)"; fi

# --- Codex ---
if have "$HOME/.codex"; then
  link "$CANON" "$HOME/.codex/AGENTS.md"
  link_skills "$HOME/.codex/skills"
else note "skip Codex (~/.codex absent)"; fi

# --- Antigravity / Gemini ---
if have "$HOME/.gemini"; then
  link "$CANON" "$HOME/.gemini/GEMINI.md"
  link "$CANON" "$HOME/.gemini/AGENTS.md"
  link_skills "$HOME/.gemini/skills"
else note "skip Gemini (~/.gemini absent)"; fi

# --- Pi (loads from its own skills dir like the others, so give it the same per-skill links) ---
if have "$HOME/.pi"; then
  link "$CANON" "$HOME/.pi/agent/AGENTS.md"
  # link() backs up any colliding pi-local real dir into backups/ before linking, so a stale
  # pi-local copy can't shadow canon. Non-canon pi-local skills are left untouched.
  link_skills "$HOME/.pi/agent/skills"
else note "skip Pi (~/.pi absent)"; fi

echo "== done. backups (if any): $BK =="
