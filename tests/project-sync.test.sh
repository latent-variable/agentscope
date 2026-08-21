#!/usr/bin/env bash
# Behavior tests for project-sync.sh's two containment guards.
#
# Both defects here are SILENT: nothing crashes, the script prints success, and
# the damage is to a file outside the repo or to another project's memory.
#
#   ESCAPE     AGENTS.md is repo-CONTROLLED, and step 6 writes THROUGH symlinks
#              on purpose (some repos keep it as a link to CLAUDE.md). A checkout
#              shipping AGENTS.md -> ~/.ssh/config therefore had that file
#              truncated and overwritten by a documented bootstrap command.
#   COLLISION  Claude's project key is the abs path with '/' -> '-', so /x/a-b/c
#              and /x/a/b-c produce the SAME key. The bridge was relinked
#              unconditionally, so the second repo silently took over the first
#              repo's memory and each then read and wrote the other's.
#
# Every refusal is paired with a control that must still succeed, so a guard that
# simply refuses everything cannot pass. The escape case also carries a
# vacuity control: the same scenario with the guard stripped out must actually
# destroy the file, or the test proves nothing.
set -uo pipefail
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bin/project-sync.sh"
[ -f "$SCRIPT" ] || { echo "project-sync.sh not found at $SCRIPT"; exit 1; }

SB="$(mktemp -d)"
# Recoverable teardown per canon: Trash, never an unbounded delete, and the guard
# stays so an empty or wrong variable cannot reach the delete at all.
trap '[ -n "${SB:-}" ] && [ -d "$SB" ] && case "$SB" in /*) [ -x /usr/bin/trash ] && /usr/bin/trash "$SB" 2>/dev/null;; esac' EXIT

FAKE_HOME="$SB/home"
mkdir -p "$FAKE_HOME/.agents/skills/example-skill" "$FAKE_HOME/.claude/projects"
: > "$FAKE_HOME/.agents/skills/example-skill/SKILL.md"

# A fresh git repo. Returns its path; caller must check.
mkrepo(){
  local d="$SB/$1"
  mkdir -p "$d/.git" || return 1
  printf '%s\n' "$d"
}
run(){ HOME="$FAKE_HOME" bash "$SCRIPT" "$1" 2>&1; }

# ── 1. ESCAPE: a symlink out of the repo is refused, and the target survives ──
repo="$(mkrepo esc)" || exit 2
outside="$SB/precious.conf"
printf 'KEEP ME\n' > "$outside"
ln -s "$outside" "$repo/AGENTS.md"
out="$(run "$repo")"; rc=$?
if [ $rc -ne 0 ] && grep -qi "outside" <<<"$out"; then
  ok "escape: refuses an AGENTS.md symlink that leaves the repo"
else no "escape: did NOT refuse (rc=$rc): $(head -2 <<<"$out")"; fi

if [ "$(cat "$outside")" = "KEEP ME" ]; then
  ok "escape: the file outside the repo is untouched"
else no "escape: OVERWROTE $outside — contents now: $(head -c 80 "$outside")"; fi

# Refusing must leave the repo as it was found, or a 'safe' refusal still litters.
if [ ! -d "$repo/.agents" ]; then
  ok "escape: refusal happens before anything is created"
else no "escape: created .agents despite refusing"; fi

# ── 2. VACUITY CONTROL: strip the guard, and the same case must destroy it ────
# Without this, a passing suite is compatible with the guard doing nothing at all.
bare="$SB/no-guard.sh"
sed '/^assert_inside_repo /d' "$SCRIPT" > "$bare"
repo2="$(mkrepo esc2)" || exit 2
outside2="$SB/precious2.conf"
printf 'KEEP ME\n' > "$outside2"
ln -s "$outside2" "$repo2/AGENTS.md"
HOME="$FAKE_HOME" bash "$bare" "$repo2" >/dev/null 2>&1
if [ "$(cat "$outside2")" != "KEEP ME" ]; then
  ok "control: with the guard removed the file IS destroyed (guard is load-bearing)"
else no "control: guard-less run left the file intact — this suite proves nothing"; fi

# ── 3. NOT over-broad: an in-repo symlink twin still works ───────────────────
repo3="$(mkrepo twin)" || exit 2
printf '# Twin\n' > "$repo3/CLAUDE.md"
ln -s "$repo3/CLAUDE.md" "$repo3/AGENTS.md"
out="$(run "$repo3")"; rc=$?
if [ $rc -eq 0 ] && grep -q "Agent context" "$repo3/CLAUDE.md"; then
  ok "twin: an in-repo AGENTS.md -> CLAUDE.md symlink is still written through"
else no "twin: refused a legitimate in-repo symlink (rc=$rc): $(head -2 <<<"$out")"; fi
if [ -L "$repo3/AGENTS.md" ]; then
  ok "twin: the symlink survives (not replaced by a regular file)"
else no "twin: symlink was replaced by a regular file"; fi

# ── 4. NOT over-broad: an ordinary repo bootstraps ───────────────────────────
repo4="$(mkrepo plain)" || exit 2
out="$(run "$repo4")"; rc=$?
if [ $rc -eq 0 ] && grep -q "Agent context" "$repo4/AGENTS.md"; then
  ok "plain: an ordinary repo bootstraps normally"
else no "plain: ordinary repo failed (rc=$rc): $(head -2 <<<"$out")"; fi

# ── 5. ESCAPE via .agents, not just AGENTS.md ────────────────────────────────
repo5="$(mkrepo esc-agents)" || exit 2
mkdir -p "$SB/elsewhere"
ln -s "$SB/elsewhere" "$repo5/.agents"
out="$(run "$repo5")"; rc=$?
if [ $rc -ne 0 ] && grep -qi "outside" <<<"$out"; then
  ok "escape: a .agents symlink that leaves the repo is refused too"
else no "escape: .agents symlink not refused (rc=$rc)"; fi

# ── 6. COLLISION: a bridge owned by another repo is not stolen ───────────────
repo6="$(mkrepo collide-a)" || exit 2
run "$repo6" >/dev/null 2>&1
enc="$(printf '%s' "$repo6" | tr '/' '-')"
bridge="$FAKE_HOME/.claude/projects/$enc/memory"
if [ -L "$bridge" ]; then ok "collision: first repo owns the bridge"; else no "collision: first repo did not create a bridge"; fi

# Point a second repo's key at the SAME bridge path to model an encoding collision.
repo7="$(mkrepo collide-b)" || exit 2
mkdir -p "$FAKE_HOME/.claude/projects/$(printf '%s' "$repo7" | tr '/' '-')"
rmdir "$FAKE_HOME/.claude/projects/$(printf '%s' "$repo7" | tr '/' '-')" 2>/dev/null
ln -sfn "$repo6/.agents/memory" "$SB/collide-marker"   # what the bridge should keep pointing at
enc7="$(printf '%s' "$repo7" | tr '/' '-')"
mkdir -p "$(dirname "$FAKE_HOME/.claude/projects/$enc7/memory")"
ln -sfn "$repo6/.agents/memory" "$FAKE_HOME/.claude/projects/$enc7/memory"
out="$(run "$repo7")"; rc=$?
if [ $rc -ne 0 ] && grep -qi "collision" <<<"$out"; then
  ok "collision: refuses to take over a bridge pointing at another repo"
else no "collision: silently stole the bridge (rc=$rc): $(head -3 <<<"$out")"; fi
if [ "$(readlink "$FAKE_HOME/.claude/projects/$enc7/memory")" = "$repo6/.agents/memory" ]; then
  ok "collision: the existing bridge still points at its original repo"
else no "collision: bridge was repointed to $(readlink "$FAKE_HOME/.claude/projects/$enc7/memory")"; fi

# ── 7. NOT over-broad: re-running the same repo is idempotent ────────────────
out="$(run "$repo6")"; rc=$?
if [ $rc -eq 0 ]; then
  ok "idempotent: re-running the owning repo does not trip the collision guard"
else no "idempotent: second run of the same repo was refused (rc=$rc): $(head -2 <<<"$out")"; fi

printf '\n  PASS=%d  FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
