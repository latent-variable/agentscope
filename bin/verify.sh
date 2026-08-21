#!/usr/bin/env bash
# Drift detector for the ~/.agents knowledge base. Reports stale references so an
# agent (or you) can self-correct. Exit 0 = clean, 1 = drift found.
# Usage: verify.sh [--paths-only|--links-only|--index-only|--repos-only]
#   AGENTS_DIR=<dir>  audit a copy instead of ~/.agents (used by the test harness).
#   --paths-only      check only referenced filesystem paths (skip symlink/git/repo,
#                     which are specific to the live install).
#   --links-only      check only memory [[cross-links]]. Same reason: the harness
#                     needs one check it can aim at a sandbox and score on its own.
#   --index-only      check only the memory index.
#   --repos-only      check only referenced GitHub repos. Lets the harness drive the
#                     REAL classifier with a stubbed `gh` instead of duplicating its
#                     patterns in a test, which is how a test goes green on a
#                     regression it was written to catch.
set -uo pipefail

AGENTS="${AGENTS_DIR:-$HOME/.agents}"
MODE=full
[ "${1:-}" = "--paths-only" ] && MODE=paths
[ "${1:-}" = "--links-only" ] && MODE=links
[ "${1:-}" = "--index-only" ] && MODE=index
[ "${1:-}" = "--repos-only" ] && MODE=repos
drift=0
# The VERIFY_* overrides below exist for the sandboxed tests, and an escape hatch
# the LIVE verifier honours is a way for ambient environment state to silence the
# real board — the same "reports CLEAN while checking nothing" failure this whole
# tool exists to catch. So they apply only when auditing a COPY, never the live
# install, and when they do apply the output says so out loud.
SANDBOX=0
[ "$(cd "$AGENTS" 2>/dev/null && pwd -P)" != "$(cd "$HOME/.agents" 2>/dev/null && pwd -P)" ] && SANDBOX=1
if [ "$SANDBOX" = 0 ] && { [ -n "${VERIFY_LINKS:-}" ] || [ -n "${VERIFY_AGENT_DIRS:-}" ]; }; then
  echo "note: VERIFY_LINKS / VERIFY_AGENT_DIRS ignored — they apply only when auditing a copy, not the live install"
  unset VERIFY_LINKS VERIFY_AGENT_DIRS
fi
note(){ printf '%s\n' "$*"; }
flag(){ printf 'DRIFT: %s\n' "$*"; drift=1; }
GREP_MD='grep -rohE --include=*.md --exclude-dir=backups'

# Claude memory path is per-machine: encoded $HOME.
ENC="$(printf '%s' "$HOME" | tr '/' '-')"
CLAUDE_MEM="$HOME/.claude/projects/$ENC/memory"

check_symlinks(){
  echo "-- symlinks (installed tools only) --"
  # VERIFY_LINKS (colon-separated, like PATH) lets a test supply its own set.
  # Without it this check reads the live install, so a sandboxed test's exit
  # status silently depended on the host's symlinks being intact and would go
  # red for a reason having nothing to do with what it was testing.
  local links=() p
  if [ -n "${VERIFY_LINKS:-}" ]; then
    local IFS=:
    for p in $VERIFY_LINKS; do [ -n "$p" ] && links+=("$p"); done
    unset IFS
  else
    [ -d "$HOME/.claude" ] && links+=("$HOME/.claude/CLAUDE.md" "$CLAUDE_MEM")
    [ -d "$HOME/.codex" ]  && links+=("$HOME/.codex/AGENTS.md")
    [ -d "$HOME/.gemini" ] && links+=("$HOME/.gemini/GEMINI.md")
    [ -d "$HOME/.pi" ]     && links+=("$HOME/.pi/agent/AGENTS.md")
  fi
  if [ "${#links[@]}" -eq 0 ]; then note "  (no agent CLIs installed yet)"; return; fi
  for p in "${links[@]}"; do
    if [ -L "$p" ] && [ -e "$p" ]; then note "  ok    $p"; else flag "broken/missing symlink $p"; fi
  done
}

check_skills(){
  echo "-- skill parity (every canon skill reaches every installed agent) --"
  local skills="$AGENTS/skills" s name d l dirs=()
  # VERIFY_AGENT_DIRS lets a test point this at sandbox agent dirs. Without it the
  # only way to keep a fixture skill from flagging was to name it after a REAL
  # canon skill, which made the sandbox depend on the host's install — renaming a
  # skill would then break an unrelated test for an unrelated reason.
  # Colon-separated, like PATH: plain word-splitting breaks on any path with a
  # space in it, and a sandbox under a directory with a space is not exotic.
  if [ -n "${VERIFY_AGENT_DIRS:-}" ]; then
    local IFS=:
    for d in $VERIFY_AGENT_DIRS; do [ -n "$d" ] && dirs+=("$d"); done
    unset IFS
  else
    [ -d "$HOME/.claude" ] && dirs+=("$HOME/.claude/skills")
    [ -d "$HOME/.codex" ]  && dirs+=("$HOME/.codex/skills")
    [ -d "$HOME/.gemini" ] && dirs+=("$HOME/.gemini/skills")
    [ -d "$HOME/.pi" ]     && dirs+=("$HOME/.pi/agent/skills")
  fi
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
  # Paths canon names on purpose while they must NOT exist (a retired repo, a
  # cautionary example). Without this they flag forever, and permanent noise
  # teaches everyone to ignore real drift. One path per line, # for comments.
  local ignore="$AGENTS/.verify-ignore-paths" skip
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in *'<'*|*'*'*|*'{{'*|*'}}'*) continue;; esac     # skip placeholders/globs
    [ "$p" = "$AGENTS" ] && continue
    skip=0
    if [ -f "$ignore" ]; then
      while IFS= read -r ig; do
        case "$ig" in ''|'#'*) continue;; esac
        ig="${ig/#\~/$HOME}"; ig="${ig%/}"
        [ "${p%/}" = "$ig" ] && { skip=1; break; }
      done < "$ignore"
    fi
    [ "$skip" = 1 ] && continue
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
    if [ -n "$(git -C "$AGENTS" status --porcelain)" ]; then
      note "  uncommitted changes present — commit them, this is your brain"
    fi
    git -C "$AGENTS" fetch -q origin 2>/dev/null || true
    local ahead; ahead=$(git -C "$AGENTS" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    [ "${ahead:-0}" -gt 0 ] && note "  $ahead local commit(s) not pushed"
    note "  ok    git repo present"
  else
    note "  (not a git repo — back it up: git init + a private remote)"
  fi
}

check_links(){
  echo "-- memory cross-links --"
  # `[[name]]` points at memory/<name>.md. Canon says link liberally, and a
  # see-also link with no file yet is deliberately fine — it marks a memory worth
  # writing. That licence does NOT cover the three cases below, each of which
  # sends an agent hunting for something it will never find:
  #
  #   TYPO    memory/<name>.md exists under a different separator or prefix. The
  #           memory directory mixes `_` and `-` with no convention (28 vs 22 on
  #           2026-08-17, no convergence since June), so agents guess and miss.
  #           Nothing is gained by renaming 50 files; catching the guess is cheaper.
  #   SKILL   the name is a skill, not a memory. Canon's form is **`name`** skill.
  #   BROKEN  the link is cited mid-sentence as where the evidence or procedure
  #           lives. That is a promise the content exists elsewhere; when it
  #           dangles the content is simply lost. A trailing "Related:" list makes
  #           no such promise, which is the line this check draws.
  # FAIL CLOSED. "Could not check" is not "clean" — a silent skip here means the
  # whole verifier exits 0 while checking none of the cross-links, which is the
  # reports-clean-while-checking-nothing failure this tool exists to catch, and
  # it shipped in the same PR that added the check. python3 is not optional in
  # this repo (canon-dupe and the suites need it), so an absent one is drift.
  if ! command -v python3 >/dev/null 2>&1; then
    flag "python3 unavailable — memory cross-links NOT checked (this is not a clean board)"
    return
  fi
  local out rc
  # BACKTICKS IN THIS HEREDOC MUST STAY BALANCED. The delimiter is quoted, so
  # nothing expands, but the enclosing $( ) still scans for backtick pairs and an
  # odd one makes bash die with "unexpected EOF" 60 lines later, pointing nowhere
  # near the cause. Only the SKILL message below has any, and they are a pair.
  out=$(AGENTS="$AGENTS" python3 - <<'PY'
import os, re, pathlib, sys
root = pathlib.Path(os.environ["AGENTS"])
mem = {p.stem for p in (root/"memory").glob("*.md")}
skills = {p.name for p in (root/"skills").iterdir() if p.is_dir()} if (root/"skills").is_dir() else set()
# Names that teach the [[…]] syntax rather than pointing at a memory.
PLACEHOLDER = {"slug", "their-slug", "pointer", "name", "some-memory"}
LINK = re.compile(r"\[\[([A-Za-z0-9._-]+)\]\]")
SEEALSO = re.compile(r"\b(?:Related|See also)\s*:", re.I)
def norm(s): return s.replace("-", "_").lower()

def in_seealso_run(line, pos):
    """Is the link at this position inside a see-also list rather than a claim?

    The licence covers a trailing Related: [[a]], [[b]]. list. It must NOT cover a
    link that merely sits after such a label:
        Related: [[optional]]; evidence is [[missing_target]].
    so measure the run BETWEEN the label and THIS link, not the whole line or the
    whole tail. Scoring the tail judges every link by the same text, so one prose
    clause at the end exempts all of them or none.

    What survives in the run is decided by an ALLOWLIST, not a word count. Counting
    let a one-word clause through ("; evidence [[b]]") which is the same defect as
    the two-word case, only shorter. A list is held together by connectors; prose is
    anything else.
    """
    CONNECTORS = {"and", "or", "plus", "also", "amp", "see", "related", "too"}
    mk = None
    for mm in SEEALSO.finditer(line):
        if mm.end() <= pos:
            mk = mm
    run = line[mk.end():pos] if mk else line[:pos]
    residue = LINK.sub(" ", run)
    residue = re.sub(r"[\s,;.:()\-\u2013\u2014*\x60\"']+", " ", residue).strip()
    return all(w.lower() in CONNECTORS for w in residue.split())

bad = []
for p in sorted(root.rglob("*.md")):
    if any(x in p.parts for x in (".git", "backups", "node_modules")): continue
    for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
        for m in LINK.finditer(line):
            t = m.group(1)
            if t in mem or t in PLACEHOLDER: continue
            rel = p.relative_to(root)
            if t in skills:
                bad.append(f"{rel}:{i}  [[{t}]] is a SKILL — write it as **`{t}`** skill"); continue
            hit = [x for x in mem if norm(x) == norm(t) or norm(x).endswith(norm(t)) or norm(t).endswith(norm(x))]
            if hit:
                bad.append(f"{rel}:{i}  [[{t}]] -> broken pointer, the memory is {hit[0]}.md"); continue
            if not in_seealso_run(line, m.start()):
                bad.append(f"{rel}:{i}  [[{t}]] cited as evidence but no such memory — write it, or state the fact here")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
  ) && rc=0 || rc=$?
  if [ "${rc:-0}" -eq 0 ]; then
    note "  ok    every load-bearing [[link]] resolves"
  else
    flag "memory cross-links point at nothing"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}

check_index(){
  echo "-- memory index --"
  local idx="$AGENTS/memory/MEMORY.md"
  [ -f "$idx" ] || { flag "no memory/MEMORY.md"; return; }
  # MAX is a MEASURED bound because the prose one did not hold. `remember` has
  # said "one line each, no content" since the start, and agents complied with
  # the letter while writing 400-char summaries — one line is trivially true of
  # any length, so it constrains nothing. Entries reached a 205-char mean before
  # anyone noticed, in the file pasted into EVERY turn of EVERY agent.
  # Sandbox-only override. A bound the LIVE verifier lets the environment relax
  # is not a bound; that is the same escape-hatch defect already fixed for
  # VERIFY_LINKS above, and it came straight back in here.
  local MAX=200
  [ "$SANDBOX" = 1 ] && MAX="${CANON_INDEX_ENTRY_MAX:-200}"
  local n=0 over=0 line len
  while IFS= read -r line; do
    case "$line" in "- ["*) ;; *) continue;; esac
    n=$((n+1)); len=${#line}
    if [ "$len" -gt "$MAX" ]; then
      over=$((over+1))
      flag "index entry ${len} chars (max ${MAX}): $(printf '%.70s' "${line#- }")..."
    fi
  done < "$idx"
  [ "$over" -gt 0 ] && note "    An index line is a HOOK: would I open this file? The rule and the"
  [ "$over" -gt 0 ] && note "    numbers belong in the body, which is not paid for on every turn."
  # Both directions. An unindexed memory is invisible; a dangling pointer sends
  # an agent hunting. This lived only as a copy-paste snippet in the cleanup
  # skill, so it ran when somebody remembered to run it.
  local f base miss=0 dead=0
  for f in "$AGENTS"/memory/*.md; do
    base="$(basename "$f")"; [ "$base" = "MEMORY.md" ] && continue
    grep -q "]($base)" "$idx" || { flag "memory not indexed: $base"; miss=$((miss+1)); }
  done
  while IFS= read -r base; do
    [ -z "$base" ] && continue
    [ -f "$AGENTS/memory/$base" ] || { flag "index points at a missing file: $base"; dead=$((dead+1)); }
  done <<< "$(grep -o '](\([a-zA-Z0-9._-]*\.md\))' "$idx" | sed 's/](//;s/)//' | sort -u)"
  [ "$over" = 0 ] && [ "$miss" = 0 ] && [ "$dead" = 0 ] && note "  ok    $n entries, all within ${MAX} chars, index and files agree"
}

check_canon_size(){
  echo "-- always-on context budget --"
  local tool="$AGENTS/bin/canon-size.sh" out
  [ -x "$tool" ] || { note "  (canon-size.sh not present — skipped)"; return; }
  # USER SCOPE ONLY. Project scope is metered too, but a repo's overage is that
  # repo's work, and holding this board red on somebody else's file is how a
  # checker stops being believed. `canon-size.sh --all` is the sweep.
  if out="$(AGENTS_DIR="$AGENTS" "$tool" --user 2>&1)"; then
    note "  ok    user scope within its always-on budget"
  else
    flag "user-scope canon over its always-on budget — it is pasted into EVERY turn of EVERY agent"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
  # Skills are on-demand, but a skill you open for nearly every task is paid for
  # nearly every task, and being unmetered is how one grows to 37k chars without
  # anyone noticing. The ceiling lives next to BUDGET_SKILL in canon-size.sh.
  # When this fires, move EVIDENCE out to skills/<name>/references/ — raising the
  # ceiling is for when what does not fit is contract, not narrative.
  if out="$(AGENTS_DIR="$AGENTS" "$tool" --skills 2>&1)"; then
    note "  ok    every skill within its budget"
  else
    flag "a skill is over budget — move the evidence to skills/<name>/references/"
    printf '%s\n' "$out" | grep -E "OVER|biggest sections|^ +[0-9,]+ " | sed 's/^/    /'
  fi
}

echo "== drift check: $AGENTS =="
if [ "$MODE" = paths ]; then
  check_paths
elif [ "$MODE" = links ]; then
  check_links
elif [ "$MODE" = repos ]; then
  check_repos
elif [ "$MODE" = index ]; then
  check_index
else
  check_symlinks; check_skills; check_paths; check_links; check_index; check_canon_size; check_repos; check_git
fi
echo "== $([ $drift -eq 0 ] && echo CLEAN || echo "DRIFT FOUND")$([ "$SANDBOX" = 1 ] && echo " (SANDBOX: $AGENTS)") =="
exit $drift
