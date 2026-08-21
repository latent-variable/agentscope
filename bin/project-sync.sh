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

# Resolve a path to an absolute, symlink-free location. The file need not exist;
# what must exist is its parent. Bounded loop, because a symlink cycle would
# otherwise hang the bootstrap.
resolve_path(){
  local p="$1" d b t i=0
  while [ $i -lt 40 ]; do
    d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
    b="$(basename "$p")"
    [ -L "$d/$b" ] || { printf '%s/%s' "${d%/}" "$b"; return 0; }
    t="$(readlink "$d/$b")"
    case "$t" in /*) p="$t";; *) p="$d/$t";; esac
    i=$((i+1))
  done
  return 1
}

# Everything this script writes must land inside the repo it was pointed at.
# AGENTS.md is repo-CONTROLLED: a checkout can ship it as a symlink, and step 6
# writes THROUGH symlinks on purpose (see the note there — some repos keep
# AGENTS.md as a link to CLAUDE.md). Following a link to ~/.ssh/config or a shell
# profile truncates that file instead. Legitimate in-repo twins still work; only
# targets that escape the repo are refused.
assert_inside_repo(){
  local label="$1" path="$2" real
  [ -e "$path" ] || [ -L "$path" ] || return 0
  real="$(resolve_path "$path")" || die "$label: cannot resolve $path (broken or looping symlink)"
  case "$real" in
    "$REPO_REAL"|"$REPO_REAL"/*) return 0 ;;
    *) die "refusing to write $label: it resolves to $real, outside $REPO_REAL.
       A repository can ship this path as a symlink; following it would overwrite a file
       outside the repo. Replace it with a regular file, or point it inside the repo." ;;
  esac
}

CHECK=0
if [ "${1:-}" = "--check" ]; then CHECK=1; shift; fi

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)" || die "no such dir: ${1:-.}"
[ -d "$REPO/.git" ] || die "not a git repo: $REPO"
REPO_REAL="$(cd "$REPO" && pwd -P)"

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

# Check every repo-controlled path we write BEFORE creating anything, so a
# refusal leaves the repo exactly as it was found.
assert_inside_repo "AGENTS.md"  "$REPO/AGENTS.md"
assert_inside_repo ".agents"    "$REPO/.agents"
assert_inside_repo ".gitignore" "$REPO/.gitignore"

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
  # Claude's key is the abs path with '/' -> '-', so two different repos CAN encode
  # to the same key: /x/a-b/c and /x/a/b-c collide. We cannot pick a different
  # encoding — the whole point is to match the directory Claude actually reads — so
  # instead refuse to take over a bridge that belongs to another repo. Silently
  # relinking is what makes one project read and write another project's memory.
  # Compare RESOLVED locations, not the stored strings. REPO is normalised with
  # `pwd`, which is logical, so the same repo reached through a symlinked path
  # spells PROJ_MEM differently on different runs — a raw string compare would
  # refuse a legitimate re-run and look exactly like the bug this guards against.
  cur="$(readlink "$CLAUDE_MEM")"
  cur_real=""; mine_real="$(resolve_path "$PROJ_MEM" 2>/dev/null || printf '%s' "$PROJ_MEM")"
  if [ -n "$cur" ] && [ -e "$cur" ]; then
    cur_real="$(resolve_path "$cur" 2>/dev/null || printf '%s' "$cur")"
  fi
  # A link whose target no longer exists is stale, not contested — take it over.
  if [ -n "$cur" ] && [ -n "$cur_real" ] && [ "$cur_real" != "$mine_real" ]; then
    die "claude memory key collision: $CLAUDE_MEM already bridges to
       $cur
       and this repo wants it for
       $PROJ_MEM
       Both repo paths encode to the same Claude project key. Bridging anyway would
       let each repo read and write the other's memory. Rename one directory so the
       encoded keys differ, or remove that link by hand if it is stale."
  fi
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
# Drop any prior managed block. Old format (no END marker) was appended last → skip heading→EOF.
# New format is delimited by END → stop skipping there. Triggering on the heading handles both.
# Write THROUGH the file (cat redirect), never `mv` over it — some repos keep
# AGENTS.md as a symlink to CLAUDE.md (single source); `mv` would replace the
# symlink with a real file and diverge the twin. `cat >` follows the link.
awk '
  /^## Agent context \(scope \+ memory\)/ {skip=1}
  /END agent-context/ {skip=0; next}
  skip==0 {print}
' "$AG" > "$AG.strip.tmp" && cat "$AG.strip.tmp" > "$AG" \
    && { [ -f "$AG.strip.tmp" ] && { trash "$AG.strip.tmp" 2>/dev/null \
         || echo "  WARN  left $AG.strip.tmp behind (trash failed); remove it by hand" >&2; }; true; }
# Trim trailing blank lines, then append fresh block.
printf '%s\n' "$(cat "$AG")" > "$AG"
cat >> "$AG" <<EOF

## Agent context (scope + memory)
$BEGIN
- You are in **PROJECT scope** (this repo). Everything that is true across projects lives in user-scope canon (\`~/.agents/AGENTS.md\` + skills) and is NOT repeated here; this file holds only what is true of THIS repo.
- \`.claude\`/\`.agents\` here may be symlinks; verify with \`readlink\` before claiming a write landed.
- Project memory + shared skills: \`.agents/\` (gitignored). Read \`.agents/memory/MEMORY.md\` first.
- This file holds project facts only. Check with \`~/.agents/bin/canon-echo.sh .\`; a real exception is marked \`<!-- canon-override: <rule> — <why> (date) -->\`.
- Refresh infra: \`~/.agents/bin/project-sync.sh .\`
$END
EOF
[ "$had" = 1 ] && note "refreshed agent-context block in AGENTS.md" || note "added agent-context block to AGENTS.md"

echo "== done. tracked change: AGENTS.md + .gitignore. everything else is gitignored. =="
