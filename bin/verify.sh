#!/usr/bin/env bash
# Drift detector for the ~/.agents knowledge base. Reports stale references so an
# agent (or you) can self-correct. Exit 0 = clean, 1 = drift found.
# Usage: verify.sh [--paths-only]
#   AGENTS_DIR=<dir>  audit a copy instead of ~/.agents (used by the test harness).
#   --paths-only      check only referenced filesystem paths (skip symlink/git/repo).
set -uo pipefail

AGENTS="${AGENTS_DIR:-$HOME/.agents}"
MODE=full
[ "${1:-}" = "--paths-only" ] && MODE=paths
drift=0
note(){ printf '%s\n' "$*"; }
flag(){ printf 'DRIFT: %s\n' "$*"; drift=1; }
GREP_MD='grep -rohE --include=*.md --exclude-dir=backups'

# Claude memory path is per-machine: encoded $HOME.
ENC="$(printf '%s' "$HOME" | tr '/' '-')"
CLAUDE_MEM="$HOME/.claude/projects/$ENC/memory"

check_symlinks(){
  echo "-- symlinks (installed tools only) --"
  # Only assert a link for a tool that's actually installed.
  declare -a links=()
  [ -d "$HOME/.claude" ] && links+=("$HOME/.claude/CLAUDE.md" "$CLAUDE_MEM")
  [ -d "$HOME/.codex" ]  && links+=("$HOME/.codex/AGENTS.md")
  [ -d "$HOME/.gemini" ] && links+=("$HOME/.gemini/GEMINI.md" "$HOME/.gemini/AGENTS.md")
  [ -d "$HOME/.pi" ]     && links+=("$HOME/.pi/agent/AGENTS.md")
  if [ "${#links[@]}" -eq 0 ]; then note "  (no known agent CLIs installed yet)"; return; fi
  for p in "${links[@]}"; do
    if [ -L "$p" ] && [ -e "$p" ]; then note "  ok    $p"; else flag "broken/missing symlink $p"; fi
  done
}

check_skills(){
  echo "-- skill parity (every canon skill reaches every installed agent) --"
  local skills="$AGENTS/skills" s name d dirs=()
  [ -d "$HOME/.claude" ] && dirs+=("$HOME/.claude/skills")
  [ -d "$HOME/.codex" ]  && dirs+=("$HOME/.codex/skills")
  [ -d "$HOME/.gemini" ] && dirs+=("$HOME/.gemini/skills")
  [ -d "$HOME/.pi" ]     && dirs+=("$HOME/.pi/agent/skills")
  if [ "${#dirs[@]}" -eq 0 ]; then note "  (no agent CLIs installed yet)"; return; fi
  for s in "$skills"/*/; do
    [ -d "$s" ] || continue
    name="$(basename "$s")"
    for d in "${dirs[@]}"; do
      [ -e "$d/$name" ] || flag "skill '$name' not reachable in $d"
    done
  done
  # any dangling skill link is dead weight a loader can trip on
  for d in "${dirs[@]}"; do
    for l in "$d"/*; do
      [ -L "$l" ] && [ ! -e "$l" ] && flag "dangling skill link $l"
    done
  done
  note "  checked $(ls -d "$skills"/*/ 2>/dev/null | wc -l | tr -d ' ') skills across ${#dirs[@]} agents"
}

check_paths(){
  echo "-- referenced paths --"
  local paths okc=0 p
  # Match ~/... and $HOME/... references in canon markdown; skip {{placeholders}} and globs.
  paths=$($GREP_MD '(~|'"$HOME"')/[A-Za-z0-9._/-]+' "$AGENTS" 2>/dev/null \
          | sed "s#^~#$HOME#; s#[.,]*\$##" | sort -u)
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in *'<'*|*'*'*|*'{{'*|*'}}'*) continue;; esac     # skip placeholders/globs
    [ "$p" = "$AGENTS" ] && continue
    if [ -e "$p" ]; then okc=$((okc+1)); else flag "path not found: $p"; fi
  done <<< "$paths"
  note "  $okc referenced paths exist"
}

check_repos(){
  echo "-- github repos --"
  if ! command -v gh >/dev/null 2>&1; then note "  (gh not available — skipped)"; return; fi
  # Derive your handle from this repo's origin, then verify any github.com/<handle>/<repo> refs in canon.
  local owner repos r
  owner=$(git -C "$AGENTS" remote get-url origin 2>/dev/null \
          | sed -E 's#(git@github.com:|https://github.com/)##; s#/.*##')
  if [ -z "$owner" ]; then note "  (no origin remote — skipped)"; return; fi
  repos=$($GREP_MD "github\.com/$owner/[A-Za-z0-9._-]+" "$AGENTS" 2>/dev/null \
          | sed 's#github.com/##; s#\.git$##' | sort -u)
  if [ -z "$repos" ]; then note "  (no $owner repo refs in canon)"; return; fi
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    if gh repo view "$r" >/dev/null 2>&1; then note "  ok    $r"; else flag "repo not found: $r"; fi
  done <<< "$repos"
}

check_git(){
  echo "-- git state --"
  if git -C "$AGENTS" rev-parse --git-dir >/dev/null 2>&1; then
    [ -n "$(git -C "$AGENTS" status --porcelain)" ] && note "  uncommitted changes present"
    git -C "$AGENTS" fetch -q origin 2>/dev/null || true
    local ahead; ahead=$(git -C "$AGENTS" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    [ "${ahead:-0}" -gt 0 ] && note "  $ahead local commit(s) not pushed"
    note "  ok    git repo present"
  else
    note "  (not a git repo — back it up: git init + a private remote)"
  fi
}

echo "== drift check: $AGENTS =="
if [ "$MODE" = paths ]; then
  check_paths
else
  check_symlinks; check_skills; check_paths; check_repos; check_git
fi
echo "== $([ $drift -eq 0 ] && echo CLEAN || echo "DRIFT FOUND") =="
exit $drift
