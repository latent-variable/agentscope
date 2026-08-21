#!/usr/bin/env bash
# Tests for bin/canon-size.sh — the always-on context meter.
#
# The dangerous failure here is not a crash, it is a meter that reads LOW: canon
# keeps growing while the board stays green. So every case below asserts a number
# or a status, never just "it ran". Fully sandboxed: synthetic canon under TMPDIR,
# budgets and roots injected by environment, real ~/.agents never read.
set -uo pipefail

TOOL="$(cd "$(dirname "$0")/.." && pwd)/bin/canon-size.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

TRASH="$(command -v trash || true)"
LEAKED=""
discard(){
  for d in "$@"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    case "$d" in /*) ;; *) continue ;; esac
    if [ -n "$TRASH" ]; then "$TRASH" "$d" >/dev/null 2>&1 || LEAKED="$LEAKED $d"
    else LEAKED="$LEAKED $d"; fi
  done
}
report_leaks(){
  [ -z "$LEAKED" ] && return 0
  printf '  \033[1;33mNOTE\033[0m  `trash` unavailable, fixtures left behind:\n'
  for d in $LEAKED; do printf '        %s\n' "$d"; done
}

SB="$(mktemp -d)"
trap 'discard "$SB"; report_leaks' EXIT

# --- synthetic canon -------------------------------------------------------
USER_SCOPE="$SB/userscope"
mkdir -p "$USER_SCOPE/memory"
mkfile(){ # mkfile <path> <chars>
  mkdir -p "$(dirname "$1")"
  head -c "$2" < /dev/zero | tr '\0' 'x' > "$1"
}
mkfile "$USER_SCOPE/AGENTS.md" 1000
mkfile "$USER_SCOPE/memory/MEMORY.md" 500

REPOS="$SB/repos"
mkrepo(){ mkdir -p "$REPOS/$1/.git"; }

run(){ AGENTS_DIR="$USER_SCOPE" CANON_ROOTS="$REPOS" \
       CANON_BUDGET_USER_CANON="${BU:-2000}" CANON_BUDGET_USER_INDEX="${BI:-2000}" \
       CANON_BUDGET_REPO_CANON="${BR:-2000}" CANON_BUDGET_REPO_INDEX="${BRI:-2000}" \
       CANON_BUDGET_SESSION="${BS:-100000}" \
       bash "$TOOL" "$@" 2>&1; }

# User-scope cases MUST pass --user. With no argument the tool also meters the
# CURRENT directory when it is a checkout, so the suite silently measured whatever
# repo it happened to run from: green in a linked worktree (.git is a FILE there,
# so the cwd branch never fired) and red in ~/.agents itself, where it billed the
# real 63k canon against the 2,000-char sandbox budget. A suite whose result
# depends on its cwd is not a suite.
user_run(){ run --user "$@"; }

echo "== canon-size =="

# 1. Everything comfortably inside budget: green board, exit 0.
out="$(run --all)"; rc=$?
if [ $rc -eq 0 ] && grep -q "within budget" <<<"$out"; then
  ok "under budget: exit 0 and says so"
else
  no "under budget: expected exit 0 + 'within budget' (rc=$rc)"
fi

# 2. Over budget MUST fail. A meter that only prints is a meter nobody obeys.
out="$(BU=500 user_run)"; rc=$?
if [ $rc -eq 1 ] && grep -q "OVER" <<<"$out"; then
  ok "over budget: exit 1 and flags OVER"
else
  no "over budget: expected exit 1 + OVER (rc=$rc)"
fi

# 3. WARN must NOT fail the board. If the warning band turned it red, the only
#    way to a green board would be to raise the budget, and the tool would be
#    training exactly the habit it exists to stop.
out="$(BU=1100 user_run)"; rc=$?
if [ $rc -eq 0 ] && grep -q "WARN" <<<"$out"; then
  ok "warn band: reports WARN but exits 0"
else
  no "warn band: expected exit 0 + WARN (rc=$rc)"
fi

# 3b. ONE char over is over. `pct = chars*100/budget` truncates, so 1001 against
#     a 1000 budget computes 100 and reported WARN — the meter reading LOW while
#     the board stayed green, which is the only failure that really costs.
mkfile "$USER_SCOPE/AGENTS.md" 1001
out="$(BU=1000 user_run)"; rc=$?
if [ $rc -eq 1 ] && grep -q "OVER" <<<"$out"; then
  ok "boundary: one char over budget is OVER, not WARN"
else
  no "boundary: 1001/1000 should be OVER + exit 1 (rc=$rc)"
fi
mkfile "$USER_SCOPE/AGENTS.md" 1000
out="$(BU=1000 user_run)"; rc=$?
if [ $rc -eq 0 ]; then
  ok "boundary: exactly at budget still passes"
else
  no "boundary: 1000/1000 should pass (rc=$rc)"
fi

# 4. CLAUDE.md is normally a symlink to AGENTS.md. Billing both doubled every
#    repo's reported cost — the meter read HIGH, which is just as useless as low.
mkrepo twin
mkfile "$REPOS/twin/AGENTS.md" 1000
ln -sf AGENTS.md "$REPOS/twin/CLAUDE.md"
out="$(run "$REPOS/twin")"
sess="$(grep 'SESS' <<<"$out" | awk '{print $2}' | tr -d ',')"
if [ "$sess" = "2500" ]; then          # 1000 user + 500 index + 1000 repo, counted ONCE
  ok "symlink twin: canon billed once (session=$sess)"
else
  no "symlink twin: session should be 2500, got '${sess:-none}'"
fi

# 4b. The mirror failure: an id that does NOT distinguish two real files. Any
#     probe returning a constant (or a filesystem-level id shared by everything on
#     the same volume) dedupes away every file after the first, and the meter reads
#     LOW while the board stays green. Two DISTINCT canon files must both bill.
mkrepo forked
mkfile "$REPOS/forked/AGENTS.md" 1000
mkfile "$REPOS/forked/CLAUDE.md" 700
out="$(run "$REPOS/forked")"
sess="$(grep 'SESS' <<<"$out" | awk '{print $2}' | tr -d ',')"
if [ "$sess" = "3200" ]; then          # 1000 user + 500 index + 1000 + 700, none deduped
  ok "distinct files: both billed (session=$sess)"
else
  no "distinct files: session should be 3200, got '${sess:-none}'"
fi

# 5. The session total is the whole point: user scope is paid in EVERY repo, so a
#    repo's own number understates what an agent actually starts with.
out="$(run "$REPOS/twin")"
if grep -qE 'SESS .*starts here' <<<"$out"; then
  ok "session total: reported per repo"
else
  no "session total: missing"
fi

# 6. Breakdown must rank by size, biggest first — that IS the work list.
{ printf '## small\n'; head -c 100 </dev/zero | tr '\0' 'x'; printf '\n'
  printf '## huge\n';  head -c 900 </dev/zero | tr '\0' 'x'; printf '\n'
  printf '## mid\n';   head -c 400 </dev/zero | tr '\0' 'x'; printf '\n'; } > "$SB/sectioned.md"
out="$(run --breakdown "$SB/sectioned.md")"
# '### sections' CONTAINS '## sections', so an unanchored match grabs both blocks.
first="$(grep -A1 -E '^ +## sections$' <<<"$out" | tail -1 | awk '{print $2}')"
if [ "$first" = "huge" ]; then
  ok "breakdown: biggest section first"
else
  no "breakdown: expected 'huge' first, got '${first:-none}'"
fi

# 7. A MEMORY.md index has no headings. Falling through to an empty list would
#    leave the one file most likely to bloat with no cut signal at all.
mkfile "$USER_SCOPE/memory/MEMORY.md" 500
{ printf -- '- [short](a.md), hook\n'
  printf -- '- [long](b.md), '; head -c 800 </dev/zero | tr '\0' 'y'; printf '\n'; } > "$USER_SCOPE/memory/MEMORY.md"
out="$(BI=200 user_run)"
if grep -q "longest lines" <<<"$out" && grep -q "yyy" <<<"$out"; then
  ok "headless index: falls back to longest lines"
else
  no "headless index: no fallback breakdown"
fi
mkfile "$USER_SCOPE/memory/MEMORY.md" 500

# 8. A linked worktree has a .git FILE. Metering it double-reports the same canon
#    under a name that reads like a separate repo, inflating the whole sweep.
mkdir -p "$REPOS/twin-wt"
echo "gitdir: $REPOS/twin/.git/worktrees/twin-wt" > "$REPOS/twin-wt/.git"
mkfile "$REPOS/twin-wt/AGENTS.md" 1000
out="$(run --all)"
if ! grep -q "twin-wt" <<<"$out"; then
  ok "worktree: linked worktree skipped in --all"
else
  no "worktree: linked worktree counted as a repo"
fi

# 9. A repo with no agent file is not a finding. Reporting one would put every
#    unwired scratch repo on the board and bury the real overages.
mkrepo bare
out="$(run --all)"
if ! grep -q "bare" <<<"$out"; then
  ok "no agent file: repo omitted"
else
  no "no agent file: repo reported anyway"
fi

# 10. The suite must give the same answer from anywhere. It did not: run from a
#     linked worktree it passed, run from ~/.agents it failed two cases, because
#     the bare invocation also meters the cwd when the cwd is a checkout.
mkfile "$USER_SCOPE/AGENTS.md" 1000
out="$(cd "$REPOS/twin" && BU=2000 user_run)"; rc=$?
if [ $rc -eq 0 ] && ! grep -q "twin" <<<"$out"; then
  ok "location: --user ignores the cwd checkout"
else
  no "location: cwd leaked into a user-scope run (rc=$rc)"
fi

# 11. Skills were entirely unmetered, which is how one real skill reached 37,684
#     chars — the single skill loaded for nearly every code task, and 28% of all
#     skill content, with nothing reporting it.
mkdir -p "$USER_SCOPE/skills/big" "$USER_SCOPE/skills/small"
mkfile "$USER_SCOPE/skills/big/SKILL.md" 3000
mkfile "$USER_SCOPE/skills/small/SKILL.md" 500
out="$(CANON_BUDGET_SKILL=1000 run --skills)"; rc=$?
if [ $rc -eq 1 ] && grep -q "OVER" <<<"$out" && grep -q "big" <<<"$out"; then
  ok "skills: an over-budget skill is reported and fails"
else
  no "skills: over-budget skill not caught (rc=$rc)"
fi
out="$(CANON_BUDGET_SKILL=1000 run --skills)"
if grep -qE "ok +500" <<<"$out"; then
  ok "skills: a small skill passes"
else
  no "skills: small skill misreported"
fi
# The skill ceiling is a DECIDED number, so changing it must be deliberate.
#
# Every other budget test injects its own value, which is right for testing the
# mechanism and means nothing pins the shipped default. That default was set once
# at whatever the biggest skill happened to weigh that day (15,000 against 14,875), and
# it then blocked a legitimate contract addition. Pinning it here does not stop
# anyone raising it — it makes them come here, read why it is 25,000, and say so.
# `env -u` is load-bearing: --budgets prints the EFFECTIVE value, so an exported
# CANON_BUDGET_SKILL (this suite exports one for other cases, and a shell can
# carry one in) would make this assert the override and call it the default —
# passing or failing for a reason that has nothing to do with the shipped number.
out="$(env -u CANON_BUDGET_SKILL bash "$TOOL" --budgets 2>&1)"
if grep -qE "CANON_BUDGET_SKILL +25000" <<<"$out"; then
  ok "budgets: the shipped skill ceiling is 25,000"
else
  no "budgets: skill ceiling changed without updating this test: $(grep -i skill <<<"$out")"
fi

# --skills must not drag the cwd checkout in, same trap as --user.
out="$(cd "$REPOS/twin" && CANON_BUDGET_SKILL=99999 run --skills)"; rc=$?
if [ $rc -eq 0 ] && ! grep -q "twin" <<<"$out"; then
  ok "skills: --skills ignores the cwd checkout"
else
  no "skills: cwd leaked into a --skills run (rc=$rc)"
fi

# 14. verify.sh must actually FAIL on an over-budget skill. A gate that reports
#     and never fails is the exact failure this line of work exists to stop, and
#     this gate went in on an already-green board, so nothing else would have
#     caught it being wired up inert.
#
#     Getting the EXIT STATUS to mean something took two fixes to the fixture,
#     and the first draft asserted the flag text instead because I had not made
#     them: a sandbox canon is not a git repo (check_git flags) and its skills are
#     not in the agent dirs (check_skills flags), so rc was 1 either way and the
#     test passed on contamination. Fixed by `git init` plus VERIFY_AGENT_DIRS
#     pointed at sandbox agent dirs. The intermediate version named the fixture
#     skill after a REAL canon skill so parity passed, which worked but made this
#     test depend on the host's install — renaming a canon skill would then break
#     it for an unrelated reason. Text is asserted alongside rc, so a red board
#     for some OTHER reason cannot masquerade as this gate working.
VSB="$(mktemp -d)"
# A space in the sandbox path is deliberate: VERIFY_AGENT_DIRS used to
# word-split, so any path with a space silently checked the wrong directories.
mkdir -p "$VSB/bin" "$VSB/skills/fixture-skill" "$VSB/memory" "$VSB/agent dir"
ln -s "$VSB/skills/fixture-skill" "$VSB/agent dir/fixture-skill"
# Its own symlink set too, so the host's install cannot decide this test's rc.
mkfile "$VSB/linktarget" 10
ln -sf "$VSB/linktarget" "$VSB/alink"
cp "$(dirname "$TOOL")/canon-size.sh" "$(dirname "$TOOL")/verify.sh" "$VSB/bin/"
mkfile "$VSB/AGENTS.md" 100
mkfile "$VSB/memory/MEMORY.md" 100
mkfile "$VSB/skills/fixture-skill/SKILL.md" 500
git -C "$VSB" init -q
git -C "$VSB" add -A >/dev/null 2>&1
git -C "$VSB" -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1

under="$(AGENTS_DIR="$VSB" VERIFY_AGENT_DIRS="$VSB/agent dir" VERIFY_LINKS="$VSB/alink" CANON_BUDGET_SKILL=1000 bash "$VSB/bin/verify.sh" 2>&1)"; under_rc=$?
mkfile "$VSB/skills/fixture-skill/SKILL.md" 5000
over="$(AGENTS_DIR="$VSB" VERIFY_AGENT_DIRS="$VSB/agent dir" VERIFY_LINKS="$VSB/alink" CANON_BUDGET_SKILL=1000 bash "$VSB/bin/verify.sh" 2>&1)"; over_rc=$?
discard "$VSB"

if [ $under_rc -eq 0 ] && grep -q "every skill within its budget" <<<"$under"; then
  ok "verify: a compliant board is genuinely green (rc=0)"
else
  no "verify: false red on skills inside budget (rc=$under_rc)"
fi
if [ $over_rc -eq 1 ] && grep -q "DRIFT: a skill is over budget" <<<"$over"; then
  ok "verify: an over-budget skill turns the board red (rc=1)"
else
  no "verify: skills gate is wired up inert (rc=$over_rc)"
fi

# 15. The test overrides must NOT work against the live install. An escape hatch
#     the live verifier honours lets an inherited or stale env var silence the
#     real board — "reports CLEAN while checking nothing", the exact failure this
#     tool exists to catch, reintroduced by the fix for the previous finding.
live="$(VERIFY_LINKS=/nonexistent/link VERIFY_AGENT_DIRS=/nonexistent/dir \
        bash "$(dirname "$TOOL")/verify.sh" 2>&1)"
if grep -q "VERIFY_LINKS / VERIFY_AGENT_DIRS ignored" <<<"$live" \
   && ! grep -q "broken/missing symlink /nonexistent/link" <<<"$live"; then
  ok "overrides: ignored against the live install, and it says so"
else
  no "overrides: honoured against the live install — ambient env can silence the board"
fi
# A sandboxed run must be unmistakable, so a clean sandbox result can never be
# read as a clean bill for the real canon.
if grep -q "SANDBOX" <<<"$under"; then
  ok "overrides: a sandboxed run is labelled SANDBOX"
else
  no "overrides: sandboxed run looks like a live clean bill"
fi

echo "--------------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ $FAIL -eq 0 ]
