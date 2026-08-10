#!/usr/bin/env bash
# Tests for bin/autopush.sh — the launchd cadence backup.
#
# It runs unattended every 30 minutes against the real canon repo, so its blast
# radius is the whole knowledge base. Everything here runs against throwaway
# repos via AGENTS_DIR; the real ~/.agents is never touched.
#
# The behaviour under test is the 2026-08-03 rescoping: it is a BACKUP, not a
# publisher. It may commit the append-only surface and nothing else, and it must
# stand down completely when someone is working on a branch.
set -uo pipefail

SCRIPT="${AUTOPUSH_SCRIPT:-$HOME/.agents/bin/autopush.sh}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

ROOTDIR="$(mktemp -d "${TMPDIR:-/tmp}/autopush-tests.XXXXXX")"

# Recoverable teardown, same contract as worktree-remove.test.sh (see the long
# note there): the sandbox goes to Trash, not to an unbounded delete. One entry
# per run, and you empty the Trash whenever you like. The path guard stays
# too — Trash makes a mistake recoverable, the guard stops it happening.
scrub_sandbox() {
  local p="$1" tmproot
  tmproot="$(cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)" || return 1
  [ -n "${p}" ] || { echo "scrub: refusing an empty path" >&2; return 1; }
  case "${p}" in /*) ;; *) echo "scrub: refusing a relative path: ${p}" >&2; return 1 ;; esac
  case "${p}" in "${tmproot}"/*|"${TMPDIR:-/tmp}"/*) ;; *) echo "scrub: refusing a path outside the temp root: ${p}" >&2; return 1 ;; esac
  case "$(basename "${p}")" in autopush-tests.*) ;; *) echo "scrub: refusing an unrecognised path: ${p}" >&2; return 1 ;; esac
  [ -e "${p}" ] || return 0
  chmod -R u+w "${p}" 2>/dev/null
  if [ -x /usr/bin/trash ]; then
    /usr/bin/trash "${p}" 2>/dev/null || echo "scrub: trash failed, leaving ${p} in place" >&2
  else
    echo "scrub: no /usr/bin/trash; leaving ${p} for you to remove" >&2
  fi
}
trap 'scrub_sandbox "${ROOTDIR}"' EXIT

# A canon-shaped repo with a real bare origin, so fetch/pull/push behave.
# Fails CLOSED. The setup block silences all output, so a failed mktemp or git
# used to leave the helper printing an empty/invalid path and returning success:
# the suite then ran every assertion against a non-existent fixture and reported
# a green that meant nothing. Setup failure must abort the run, not decorate it.
new_canon() {
  local r
  r="$(mktemp -d "${ROOTDIR}/canonXXXXXX")" || { echo "FATAL: mktemp failed" >&2; return 1; }
  [ -d "${r}" ] || { echo "FATAL: fixture dir missing: ${r}" >&2; return 1; }
  {
    cd "${r}" || exit 1
    git init -q -b main
    printf 'backups/\n' > .gitignore
    mkdir -p memory bin skills tests
    echo "# index" > memory/MEMORY.md
    echo "canon"   > AGENTS.md
    echo "echo hi" > bin/tool.sh
    echo '{}'      > trello-boards.json
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    git init -q --bare "${r}.git"
    git remote add origin "${r}.git"
    git push -q origin main
    git remote set-head origin main
    git branch --set-upstream-to=origin/main main
  } >/dev/null 2>&1
  # Assert the fixture is actually usable before handing it out.
  git -C "${r}" rev-parse --verify HEAD >/dev/null 2>&1 \
    || { echo "FATAL: fixture repo has no commit: ${r}" >&2; return 1; }
  [ -d "${r}.git" ] || { echo "FATAL: fixture origin missing: ${r}.git" >&2; return 1; }
  printf '%s' "${r}"
}

# Every call site goes through this, so a setup failure stops the suite instead
# of producing assertions against a path that does not exist.
canon_or_die() {
  local r; r="$(new_canon)" || { echo "aborting: fixture setup failed" >&2; exit 2; }
  [ -n "${r}" ] || { echo "aborting: fixture setup returned an empty path" >&2; exit 2; }
  printf '%s' "${r}"
}

run(){ AGENTS_DIR="$1" bash "${SCRIPT}" 2>&1; }
head_msg(){ git -C "$1" log -1 --format=%s; }
count(){ git -C "$1" rev-list --count HEAD; }
# Capture, then match. `git ... | grep -q` under `set -o pipefail` is a trap:
# grep exits on the first match, git takes SIGPIPE (141), and pipefail hands the
# whole pipeline that 141 — so a SUCCESSFUL match reads as a failed test,
# nondeterministically, depending on whether the writer had finished. Cost an
# hour here; never pipe into grep -q inside a conditional.
origin_log(){ git -C "$1.git" log --oneline main 2>/dev/null || true; }
files_in_head(){ git -C "$1" log -1 --name-only --format= 2>/dev/null || true; }
porcelain(){ git -C "$1" status --porcelain 2>/dev/null || true; }

echo "############ autopush.sh — backup, not publisher ############"

# ── clean tree: nothing to do ────────────────────────────────────────────────
R="$(canon_or_die)"; before="$(count "${R}")"
run "${R}" >/dev/null
[ "$(count "${R}")" = "${before}" ] && ok "clean: makes no commit" || no "clean: committed something"

# ── memory/ is the append-only surface: auto-committed ───────────────────────
R="$(canon_or_die)"; before="$(count "${R}")"
echo "a durable fact" > "${R}/memory/new_fact.md"
out="$(run "${R}")"
if [ "$(count "${R}")" -gt "${before}" ]; then ok "memory: a forgotten memory file is backed up"
else no "memory: not committed: ${out}"; fi
if grep -q 'memory/new_fact.md' <<<"$(head_msg "${R}")"; then
  ok "memory: commit message NAMES the file (not 'sync canon')"
else no "memory: generic message: $(head_msg "${R}")"; fi

# ── bin/ is code: HELD, never swept ──────────────────────────────────────────
R="$(canon_or_die)"; before="$(count "${R}")"
echo "rm -rf /" >> "${R}/bin/tool.sh"
out="$(run "${R}")"
[ "$(count "${R}")" = "${before}" ] && ok "code: bin/ change is NOT auto-committed" || no "code: swept bin/ onto main"
grep -q 'HOLDING' <<<"${out}" && ok "code: holds it loudly in the log" || no "code: silently ignored it: ${out}"
grep -q 'bin/tool.sh' <<<"${out}" && ok "code: names the held path" || no "code: did not name the path"

# ── AGENTS.md and skills/ are prose with rationale: also held ────────────────
R="$(canon_or_die)"; before="$(count "${R}")"
echo "new rule" >> "${R}/AGENTS.md"; echo "s" > "${R}/skills/x.md"
run "${R}" >/dev/null
[ "$(count "${R}")" = "${before}" ] && ok "prose: AGENTS.md + skills/ are held, not swept" || no "prose: swept them"

# ── mixed: back up the safe half, hold the rest ──────────────────────────────
R="$(canon_or_die)"; before="$(count "${R}")"
echo "fact" > "${R}/memory/f.md"; echo "code" >> "${R}/bin/tool.sh"
out="$(run "${R}")"
if [ "$(count "${R}")" -gt "${before}" ] && ! grep -q 'bin/tool.sh' <<<"$(files_in_head "${R}")"; then
  ok "mixed: commits memory/ only, leaves bin/ dirty"
else no "mixed: wrong split: $(files_in_head "${R}")"; fi
grep -q 'bin/tool.sh' <<<"$(porcelain "${R}")" && ok "mixed: bin/ still uncommitted for a human" || no "mixed: bin/ disappeared"

# ── STAGED code must not ride along with an allowed memory commit ────────────
# The rescope added the allowlist to `git add`, but a bare `git commit` ships the
# whole INDEX. So code an agent had already staged reached the default branch
# under an "auto:" message anyway — the precise bypass this exists to stop.
# Only an unstaged bin/ edit was covered, which is why it went unnoticed.
R="$(canon_or_die)"
echo "staged code" >> "${R}/bin/tool.sh"
git -C "${R}" add bin/tool.sh >/dev/null 2>&1          # STAGED, deliberately
echo "a fact" > "${R}/memory/late.md"                  # dirty allowlisted path
run "${R}" >/dev/null
if ! grep -q 'bin/tool.sh' <<<"$(files_in_head "${R}")"; then
  ok "staged: staged code does NOT ride along with the memory commit"
else no "staged: published staged code to the default branch"; fi
if grep -q 'memory/late.md' <<<"$(files_in_head "${R}")"; then
  ok "staged: the memory file was still backed up"
else no "staged: memory file missed"; fi
if grep -qE '^[AM]' <<<"$(porcelain "${R}")"; then
  ok "staged: the agent's staged work is left staged, untouched"
else no "staged: disturbed the index"; fi

# ── a failed commit must not unstage someone else's staged work ──────────────
# The old failure branch ran a bare `git reset`, blowing away an index the script
# had just declared outside its authority. Forced here with an unwritable
# .git/COMMIT_EDITMSG path via a failing pre-commit hook.
R="$(canon_or_die)"
mkdir -p "${R}/.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "${R}/.git/hooks/pre-commit"; chmod +x "${R}/.git/hooks/pre-commit"
echo "code" >> "${R}/bin/tool.sh"; git -C "${R}" add bin/tool.sh >/dev/null 2>&1
echo "fact" > "${R}/memory/x.md"
run "${R}" >/dev/null
if grep -qE '^[AM]  bin/tool.sh' <<<"$(porcelain "${R}")"; then
  ok "reset: a failed commit leaves other staged work staged"
else no "reset: unstaged work it had no authority over: $(porcelain "${R}")"; fi

# ── on a branch: stand down entirely ─────────────────────────────────────────
R="$(canon_or_die)"; before="$(count "${R}")"
git -C "${R}" checkout -q -b feat/agent-work
echo "wip fact" > "${R}/memory/wip.md"; echo "wip" >> "${R}/bin/tool.sh"
out="$(run "${R}")"
[ "$(count "${R}")" = "${before}" ] && ok "branch: commits NOTHING while on a branch" || no "branch: committed onto a branch"
grep -q 'standing down' <<<"${out}" && ok "branch: says why it stood down" || no "branch: no explanation: ${out}"
[ -f "${R}/memory/wip.md" ] && ok "branch: leaves in-progress work untouched" || no "branch: work vanished"

# ── deliberate commits still get pushed (that is the backup job) ─────────────
R="$(canon_or_die)"
echo "real work" > "${R}/memory/deliberate.md"
git -C "${R}" add -A >/dev/null 2>&1
git -C "${R}" -c user.email=t@t -c user.name=t commit -qm "memory: a real message" >/dev/null 2>&1
out="$(run "${R}")"
if grep -q "a real message" <<<"$(origin_log "${R}")"; then
  ok "push: a deliberate commit is pushed to origin"
else no "push: deliberate commit not pushed: ${out}"; fi

# ── held work must NOT trigger an autostash rebase ───────────────────────────
R="$(canon_or_die)"
echo "held" >> "${R}/bin/tool.sh"
out="$(run "${R}")"
grep -q 'skipping rebase' <<<"${out}" && ok "rebase: skipped while uncommitted work is present" || no "rebase: did not skip: ${out}"
grep -q 'held' "${R}/bin/tool.sh" && ok "rebase: uncommitted edit survived intact" || no "rebase: edit was lost"

# ── work appearing AFTER the initial scan must still block the rebase ────────
# The decision used to read a snapshot taken before the commit and the network
# fetch. An agent editing inside that window was invisible, and autostash would
# stash and reapply its work. A pre-commit hook is a deterministic stand-in for
# "something happened between the scan and the pull".
R="$(canon_or_die)"
mkdir -p "${R}/.git/hooks"
cat > "${R}/.git/hooks/post-commit" <<'HOOK'
#!/bin/sh
echo "appeared mid-run" >> bin/tool.sh
HOOK
chmod +x "${R}/.git/hooks/post-commit"
echo "fact" > "${R}/memory/trigger.md"
out="$(run "${R}")"
if grep -q 'skipping rebase' <<<"${out}"; then
  ok "rebase: work appearing mid-run still blocks autostash"
else no "rebase: rebased over work created after the scan: ${out}"; fi
grep -q 'appeared mid-run' "${R}/bin/tool.sh" && ok "rebase: that late edit survived" || no "rebase: late edit lost"

# ── detached HEAD is not the default branch: stand down ──────────────────────
R="$(canon_or_die)"; before="$(count "${R}")"
git -C "${R}" checkout -q --detach HEAD
echo "x" > "${R}/memory/detached.md"
run "${R}" >/dev/null
[ "$(count "${R}")" = "${before}" ] && ok "detached: stands down on a detached HEAD" || no "detached: committed anyway"

echo "--------------------------------------------"
printf 'PASS=%d  FAIL=%d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
