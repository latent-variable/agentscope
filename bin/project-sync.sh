#!/usr/bin/env bash
# Bootstrap PROJECT-scope agent context in one repo. Idempotent. Mirrors sync.sh at repo granularity.
# Wires every agent (Claude, codex, gemini, pi) to one shared, gitignored project memory + the canon skills.
#
# Usage: project-sync.sh <repo-dir>   (default: .)
#        project-sync.sh --check <repo-dir>
set -euo pipefail

AGENTS="$HOME/.agents"
SKILLS="$AGENTS/skills"

note(){ printf '  %s\n' "$*"; }
die(){ printf 'error: %s\n' "$*" >&2; exit 1; }

CHECK=0
if [ "${1:-}" = "--check" ]; then CHECK=1; shift; fi

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || die "no such dir: ${1:-.}"
[ -d "$REPO/.git" ] || die "not a git repo: $REPO"

# Claude encodes a project's memory path as the abs cwd with '/' -> '-'.
ENC="$(printf '%s' "$REPO" | tr '/' '-')"
CLAUDE_MEM="$HOME/.claude/projects/$ENC/memory"
PROJ_MEM="$REPO/.agents/memory"
PROJ_SKILLS="$REPO/.agents/skills"

if [ "$CHECK" = 1 ]; then
  echo "== project-scope check: $REPO =="
  for p in "$PROJ_MEM" "$PROJ_SKILLS" "$CLAUDE_MEM"; do
    if [ -L "$p" ]; then printf '  OK    %s -> %s\n' "$p" "$(readlink "$p")";
    elif [ -d "$p" ]; then printf '  DIR   %s (real dir, not linked)\n' "$p";
    else printf '  MISS  %s\n' "$p"; fi
  done
  grep -qxF '.agents/' "$REPO/.gitignore" 2>/dev/null && note "gitignore: .agents/ ok" || note "gitignore: .agents/ MISSING"
  grep -qxF '.claude/' "$REPO/.gitignore" 2>/dev/null && note "gitignore: .claude/ ok" || note "gitignore: .claude/ MISSING"
  exit 0
fi

echo "== bootstrapping project scope in $REPO =="

# 1. Dirs
mkdir -p "$PROJ_MEM" "$PROJ_SKILLS"

# 2. Shared canon skills -> in-repo (in-cwd discovery for pi/codex). Per-skill symlinks.
for s in "$SKILLS"/*/; do
  [ -d "$s" ] || continue
  ln -sfn "${s%/}" "$PROJ_SKILLS/$(basename "$s")"
done
note "linked $(ls -1 "$PROJ_SKILLS" | wc -l | tr -d ' ') canon skills -> .agents/skills"

# 3. Bridge Claude's per-repo memory dir -> the in-repo shared dir, preserving any existing memories.
if [ -L "$CLAUDE_MEM" ]; then
  ln -sfn "$PROJ_MEM" "$CLAUDE_MEM"; note "relinked claude memory -> .agents/memory"
elif [ -d "$CLAUDE_MEM" ]; then
  shopt -s dotglob nullglob 2>/dev/null || true
  for f in "$CLAUDE_MEM"/*; do mv -n "$f" "$PROJ_MEM/" 2>/dev/null || true; done
  rmdir "$CLAUDE_MEM" 2>/dev/null || { mv "$CLAUDE_MEM" "$CLAUDE_MEM.pre-bridge.$(date +%s)"; }
  ln -s "$PROJ_MEM" "$CLAUDE_MEM"; note "migrated + bridged claude memory -> .agents/memory"
else
  mkdir -p "$(dirname "$CLAUDE_MEM")"
  ln -s "$PROJ_MEM" "$CLAUDE_MEM"; note "bridged claude memory -> .agents/memory"
fi

# 4. .gitignore — never commit the project agent dirs.
GI="$REPO/.gitignore"; touch "$GI"
for pat in '.agents/' '.claude/'; do
  grep -qxF "$pat" "$GI" || { printf '%s\n' "$pat" >> "$GI"; note "gitignore += $pat"; }
done

# 5. Seed memory index + layout explainer (only if absent).
if [ ! -f "$PROJ_MEM/MEMORY.md" ]; then
  cat > "$PROJ_MEM/MEMORY.md" <<EOF
# Project memory — $(basename "$REPO")

Read this first; it indexes per-project memories. PROJECT scope (this repo only).
User-scope canon lives at ~/.agents and transcends projects — keep the two separate.
One line per memory below.
EOF
  note "seeded .agents/memory/MEMORY.md"
fi
if [ ! -f "$REPO/.agents/README.md" ]; then
  cat > "$REPO/.agents/README.md" <<'EOF'
# .agents/ — project-scope agent context (gitignored)

Shared by every agent (Claude, codex, gemini, pi) working in THIS repo.

- `memory/` — project memories. All agents read+write here. `~/.claude/projects/<enc>/memory`
  is symlinked to it, so Claude's auto-memory lands here too. Read `memory/MEMORY.md` first.
- `skills/` — symlinks to the canon skills in `~/.agents/skills`.

PROJECT vs USER scope: this dir is THIS repo. User-scope canon = `~/.agents` (global, all
projects). Don't conflate them. These are symlinks — verify with `readlink` before claiming
a write landed somewhere. Refresh: `~/.agents/bin/project-sync.sh .`
EOF
  note "seeded .agents/README.md"
fi

# 6. Agent-context block in the repo's AGENTS.md (the one git-tracked change).
#    Delimited + refreshable: strip any prior managed block, then re-append the current one.
AG="$REPO/AGENTS.md"; touch "$AG"
BEGIN='<!-- BEGIN agent-context (managed by ~/.agents/bin/project-sync.sh) -->'
END='<!-- END agent-context -->'
had=0; grep -qF 'Agent context (scope + memory)' "$AG" && had=1
# Write THROUGH the file (cat redirect), never `mv` over it — some repos keep AGENTS.md as a
# symlink to CLAUDE.md (single source); `mv` would replace the symlink with a real file.
awk '
  /^## Agent context \(scope \+ memory\)/ {skip=1}
  /END agent-context/ {skip=0; next}
  skip==0 {print}
' "$AG" > "$AG.strip.tmp" && cat "$AG.strip.tmp" > "$AG" && rm -f "$AG.strip.tmp"
printf '%s\n' "$(cat "$AG")" > "$AG"
cat >> "$AG" <<EOF

## Agent context (scope + memory)
$BEGIN
- You are in **PROJECT scope** (this repo). User-scope canon = \`~/.agents\` and transcends projects — don't conflate them. \`.claude\`/\`.agents\` here may be symlinks; verify with \`readlink\` before claiming a write landed.
- Project memory + shared skills: \`.agents/\` (gitignored). Read \`.agents/memory/MEMORY.md\` first.
- **Commit proactively** (canon doctrine): finished+tested chunk → commit. Commits are free and revertible. Uncommitted / branch-stranded work is invisible to anything that audits the default branch.
- Refresh infra: \`~/.agents/bin/project-sync.sh .\`
$END
EOF
[ "$had" = 1 ] && note "refreshed agent-context block in AGENTS.md" || note "added agent-context block to AGENTS.md"

echo "== done. tracked change: AGENTS.md + .gitignore. everything else is gitignored. =="
