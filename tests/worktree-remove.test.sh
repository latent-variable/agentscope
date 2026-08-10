#!/usr/bin/env bash
# Tests for `worktree.sh --remove` / `--gc`.
#
# Everything runs against throwaway repos under $TMPDIR. Real repos, real canon
# and the real Trash are never touched: safe_delete is stubbed to a plain move so
# a test run cannot fill your Trash with fixtures.
#
# The two cases that matter are the two real failure modes of `git worktree
# remove`, both observed in real repos:
#   A. refuses on an untracked non-ignored file and leaves the worktree intact
#   B. exits 0 while a live process re-creates the directory behind it
set -uo pipefail

WT="${WT_SCRIPT:-$HOME/.agents/bin/worktree.sh}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

ROOTDIR="$(mktemp -d "${TMPDIR:-/tmp}/wt-tests.XXXXXX")"

# Sandbox teardown is a RECOVERABLE delete, like every other delete in canon.
#
# A test sandbox looks like a fair exception, because trashing fixtures puts a
# directory in your Trash on every run. It is not one: emptying the Trash is one
# gesture you can make whenever you like, while
# an unbounded delete that goes wrong is unrecoverable forever. The asymmetry is
# the whole point, and the noise objection was never worth it anyway — the whole
# run lives under ONE root, so this is one Trash entry per run, not one per
# fixture. Do not reintroduce an exemption here.
#
# /usr/bin/trash by absolute path on purpose: this suite puts a `trash` STUB on
# PATH for the code under test, and the stub moves things INSIDE the sandbox we
# are trying to remove.
#
# The path guard stays as well. Trash makes a mistake recoverable; the guard
# stops the mistake. Refuses anything empty, relative, outside the temp root, or
# not carrying a prefix this suite created.
scrub_sandbox() {
  local p="$1" tmproot
  tmproot="$(cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)" || return 1
  [ -n "${p}" ] || { echo "scrub: refusing an empty path" >&2; return 1; }
  case "${p}" in /*) ;; *) echo "scrub: refusing a relative path: ${p}" >&2; return 1 ;; esac
  case "${p}" in "${tmproot}"/*|"${TMPDIR:-/tmp}"/*) ;; *) echo "scrub: refusing a path outside the temp root: ${p}" >&2; return 1 ;; esac
  case "$(basename "${p}")" in wt-tests.*|*-tmp-residue) ;; *) echo "scrub: refusing an unrecognised path: ${p}" >&2; return 1 ;; esac
  [ -e "${p}" ] || return 0
  chmod -R u+w "${p}" 2>/dev/null
  if [ -x /usr/bin/trash ]; then
    /usr/bin/trash "${p}" 2>/dev/null || echo "scrub: trash failed, leaving ${p} in place" >&2
  else
    echo "scrub: no /usr/bin/trash; leaving ${p} for you to remove" >&2
  fi
}
trap 'scrub_sandbox "${ROOTDIR}"' EXIT

# A `trash` that moves into the sandbox instead of the real Trash.
BINSTUB="${ROOTDIR}/bin"; mkdir -p "${BINSTUB}" "${ROOTDIR}/trashed"
# Faithful double for /usr/bin/trash: accepts its flags and reproduces its
# `# Moved "src" to "dst"` verbose line, so the stub cannot pass while the real
# command would fail on the same invocation.
cat > "${BINSTUB}/trash" <<STUB
#!/usr/bin/env bash
verbose=0
args=()
for a in "\$@"; do
  case "\$a" in
    -v|--verbose) verbose=1 ;;
    -s|--stopOnError) ;;
    -h|--help) echo "usage: trash [-v] FILE..."; exit 0 ;;
    *) args+=("\$a") ;;
  esac
done
for t in "\${args[@]}"; do
  dest="${ROOTDIR}/trashed/\$(basename "\$t").\$RANDOM"
  mv "\$t" "\$dest" || exit 1
  [ "\$verbose" = 1 ] && echo "# Moved \\"\$t\\" to \\"\$dest\\""
done
exit 0
STUB
chmod +x "${BINSTUB}/trash"
export PATH="${BINSTUB}:${PATH}"

# Echoes ONLY the repo path on stdout. Every git command is silenced, because
# this is called as $(new_repo) and any stray output becomes part of the path.
# It also runs in a subshell, so it must not depend on shell state persisting.
# Fails CLOSED: the setup block silences everything, so an unchecked mktemp or a
# failed git left this printing an invalid path and returning success. Every
# assertion then ran against a fixture that did not exist and the suite reported
# a green that proved nothing.
new_repo() {
  local r
  r="$(mktemp -d "${ROOTDIR}/repoXXXXXX")" || { echo "FATAL: mktemp failed" >&2; return 1; }
  [ -d "${r}" ] || { echo "FATAL: fixture dir missing: ${r}" >&2; return 1; }
  {
    cd "${r}" || exit 1
    git init -q -b main
    printf 'node_modules/\n.env.local\nfrontend/.vite/\n' > .gitignore
    echo hi > a.txt
    git add -A
    git -c user.email=t@t -c user.name=t commit -qm init
    # a bare "origin" so origin/HEAD resolves the way it does in a real clone
    git init -q --bare "${r}.git"
    git remote add origin "${r}.git"
    git push -q origin main
    git remote set-head origin main
  } >/dev/null 2>&1
  git -C "${r}" rev-parse --verify HEAD >/dev/null 2>&1 \
    || { echo "FATAL: fixture repo has no commit: ${r}" >&2; return 1; }
  printf '%s' "${r}"
}

# Every call site goes through this, so setup failure stops the suite rather
# than producing assertions against a path that does not exist.
repo_or_die() {
  local r; r="$(new_repo)" || { echo "aborting: fixture setup failed" >&2; exit 2; }
  [ -n "${r}" ] || { echo "aborting: fixture setup returned an empty path" >&2; exit 2; }
  printf '%s' "${r}"
}

echo "############ worktree.sh --remove / --gc ############"

# ── A. untracked non-ignored file: git refuses, we must not ──────────────────
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-a "${R}-feat-a" main
echo 'scratch analysis' > "${R}-feat-a/notes.md"          # untracked, not ignored

git worktree remove "${R}-feat-a" >/dev/null 2>&1
if [ -d "${R}-feat-a" ]; then
  ok "baseline: plain 'git worktree remove' refuses and leaves the worktree (failure mode A)"
else
  no "baseline: expected git to refuse on an untracked file"
fi

"${WT}" --remove "${R}-feat-a" >/dev/null 2>&1
if [ ! -e "${R}-feat-a" ]; then ok "A: --remove clears a worktree git refuses to touch"
else no "A: --remove left ${R}-feat-a behind"; fi
wt_list="$(git worktree list --porcelain)"
if ! grep -q "feat-a" <<<"${wt_list}"; then
  ok "A: git metadata deregistered"
else no "A: git still lists the removed worktree"; fi
# THE ASSERTION THIS SUITE WAS MISSING. "Gone from disk" was checked; "still
# recoverable" was not, and the two came apart: the first version called
# `git worktree remove --force`, which UNLINKS untracked and ignored files
# outright. notes.md was destroyed, the test saw an empty path, and passed.
# A recoverable-delete promise needs an assertion that the bytes still exist.
if find "${ROOTDIR}/trashed" -name 'notes.md' 2>/dev/null | grep -q .; then
  ok "A: untracked work went to Trash, NOT unlinked by git"
else
  no "A: untracked notes.md was permanently deleted (not recoverable)"
fi

# ── B. live process re-creates the directory: git exits 0, dir survives ───────
R="$(repo_or_die)"; cd "${R}"
# Created through worktree.sh, as canon requires, so the provenance record
# exists — that is the real-world shape of this failure, and --gc must be able
# to clean up after it without a --force.
"${WT}" feat-b >/dev/null 2>&1
( sleep 0.4; mkdir -p "${R}-feat-b/frontend/.vite/deps"; echo '{}' > "${R}-feat-b/frontend/.vite/deps/_metadata.json" ) &
RACER=$!
git worktree remove "${R}-feat-b" >/dev/null 2>&1; rc=$?
wait "${RACER}" 2>/dev/null
if [ "${rc}" -eq 0 ] && [ -d "${R}-feat-b" ]; then
  ok "baseline: 'git worktree remove' exits 0 yet leaves an orphan dir (failure mode B)"
else
  no "baseline: expected exit 0 with surviving directory, got rc=${rc} exists=$([ -d "${R}-feat-b" ] && echo yes || echo no)"
fi
if ! git worktree list --porcelain | grep -q "feat-b"; then
  ok "baseline: git has already forgotten the orphan, so prune will never find it"
else no "baseline: expected git to have deregistered it"; fi

# --gc REPORTS by default and must not delete anything
out="$("${WT}" --gc 2>&1)"
if [ -d "${R}-feat-b" ] && grep -q 'feat-b' <<<"${out}"; then
  ok "B: --gc reports the orphan without deleting it"
else no "B: --gc deleted without --clean, or did not report: ${out}"; fi
# --clean performs it
out="$("${WT}" --gc --clean 2>&1)"
if [ ! -e "${R}-feat-b" ]; then ok "B: --gc --clean trashes the orphan directory"
else no "B: --gc --clean left the orphan: ${out}"; fi

# ── --gc on a clean repo says so and changes nothing ─────────────────────────
R="$(repo_or_die)"; cd "${R}"
out="$("${WT}" --gc 2>&1)"
if printf '%s' "${out}" | grep -q "No residue"; then ok "gc: clean repo reports no residue"
else no "gc: expected 'No residue', got: ${out}"; fi

# ── a sibling clone that merely matches the name prefix is NEVER touched ─────
R="$(repo_or_die)"; cd "${R}"
git clone -q "${R}.git" "${R}-sibling-clone" 2>/dev/null
"${WT}" --gc --clean >/dev/null 2>&1
if [ -d "${R}-sibling-clone/.git" ]; then ok "gc: leaves a real sibling clone alone"
else no "gc: DESTROYED a sibling clone"; fi

# ── a PLAIN sibling folder matching <repo>-* is not residue either ───────────
# Name prefix + no .git was the whole old identity test, so an ordinary notes
# folder satisfied it completely and got trashed. Residue is identified by its
# CONTENTS being files this repo ignores.
R="$(repo_or_die)"; cd "${R}"
mkdir -p "${R}-notes"; echo "my research" > "${R}-notes/plan.md"
"${WT}" --gc --clean >/dev/null 2>&1
if [ -f "${R}-notes/plan.md" ]; then ok "gc: leaves an unrelated <repo>-* folder alone"
else no "gc: TRASHED an unrelated folder that just matched the name"; fi

# ── an EMPTY sibling is not residue, it is absence of evidence ──────────────
# `-type f` over an empty directory yields nothing, the validation loop never
# runs, and the function fell through to "yes, residue" — on a code path that
# deletes. Vacuous truth pointed at a delete.
R="$(repo_or_die)"; cd "${R}"
mkdir -p "${R}-emptydir"
"${WT}" --gc --clean >/dev/null 2>&1
[ -d "${R}-emptydir" ] && ok "gc: an empty <repo>-* directory is not treated as residue" || no "gc: TRASHED an empty directory"

# ── a folder of only SYMLINKS is not residue either ─────────────────────────
# Same hole by a different route: `-type f` does not match symlinks.
R="$(repo_or_die)"; cd "${R}"
mkdir -p "${R}-links"; ln -s /etc/hosts "${R}-links/link"
"${WT}" --gc --clean >/dev/null 2>&1
[ -e "${R}-links/link" ] && ok "gc: a symlink-only directory is not treated as residue" || no "gc: TRASHED a symlink-only directory"

# ── an ignored-only folder we did NOT create is reported, not deleted ───────
# The last hole in the structural test: a sibling `<repo>-build` holding only
# node_modules and .env.local passes every shape check and is somebody's work.
# Shape narrows the field; only provenance authorises a delete.
R="$(repo_or_die)"; cd "${R}"
mkdir -p "${R}-strangers-cache/frontend/.vite/deps"
echo '{}' > "${R}-strangers-cache/frontend/.vite/deps/_metadata.json"
out="$("${WT}" --gc --clean 2>&1)"
if [ -d "${R}-strangers-cache" ]; then ok "gc: an ignored-only dir we did not create is NOT deleted"
else no "gc: deleted a directory with no provenance record"; fi
grep -q 'no provenance record' <<<"${out}" && ok "gc: says why it left it alone" || no "gc: no explanation: ${out}"
"${WT}" --gc --clean --force >/dev/null 2>&1
[ ! -e "${R}-strangers-cache" ] && ok "gc: --force still removes it explicitly" || no "gc: --force did not remove"

# ── a record whose directory vanished is dropped, so the path is safe again ──
# Identity is the path (inode matching breaks failure mode B, see worktree.sh),
# so the reuse window is closed from the other end: once a recorded path stops
# existing, --gc drops the record and cannot authorize whatever appears there
# next.
R="$(repo_or_die)"; cd "${R}"
"${WT}" reuse/probe >/dev/null 2>&1
REUSED="$(dirname "${R}")/$(basename "${R}")-reuse-probe"
if [ -d "${REUSED}" ]; then
  git worktree remove --force "${REUSED}" >/dev/null 2>&1 || true   # skips our teardown; record survives
  [ -d "${REUSED}" ] || "${WT}" --gc --clean >/dev/null 2>&1        # --clean is what prunes; plain --gc is read-only
  mkdir -p "${REUSED}/frontend/.vite"                               # someone else's directory, same path
  echo '{}' > "${REUSED}/frontend/.vite/x.json"
  "${WT}" --gc --clean >/dev/null 2>&1
  [ -d "${REUSED}" ] && ok "provenance: a stale record is dropped, so a reused path is not deleted" || no "provenance: deleted a directory on a stale path record"
  scrub_sandbox "${REUSED}" 2>/dev/null || true
else
  no "provenance: setup failed, worktree not created"
fi

# ── report-only --gc must not mutate the provenance registry ────────────────
# It advertises report-only, so it has to leave shared state alone. Rewriting a
# file other agents append to, during a read-only report, is a defect on its own
# terms regardless of what the rewrite does.
R="$(repo_or_die)"; cd "${R}"
"${WT}" untouched/probe >/dev/null 2>&1
UNTOUCHED="$(dirname "${R}")/$(basename "${R}")-untouched-probe"
PROV="$(git rev-parse --git-common-dir)/agents-worktrees"
case "${PROV}" in /*) ;; *) PROV="${R}/${PROV}" ;; esac
# A STALE record has to be present or there is nothing for a prune to remove,
# and the assertion passes whether or not --gc mutates. (First version of this
# test did exactly that; the control run caught it.)
git worktree remove --force "${UNTOUCHED}" >/dev/null 2>&1 || true
if [ -f "${PROV}" ] && grep -q . "${PROV}" && [ ! -d "${UNTOUCHED}" ]; then
  before_prov="$(cat "${PROV}")"
  "${WT}" --gc >/dev/null 2>&1
  [ "$(cat "${PROV}")" = "${before_prov}" ] && ok "gc: report-only leaves the provenance registry untouched" \
    || no "gc: report-only rewrote shared provenance state"
  # ...and --clean is what actually prunes it.
  "${WT}" --gc --clean >/dev/null 2>&1
  [ "$(cat "${PROV}")" != "${before_prov}" ] && ok "gc: --clean does prune the stale record" \
    || no "gc: --clean failed to prune a dangling record"
else
  no "gc: could not stage a stale provenance record"
fi

# ── a worktree WE created is cleaned without --force ────────────────────────
R="$(repo_or_die)"; cd "${R}"
"${WT}" mine/branch >/dev/null 2>&1
MINE="$(dirname "${R}")/$(basename "${R}")-mine-branch"
[ -d "${MINE}" ] && ok "provenance: worktree.sh created ${MINE##*/}" || no "provenance: creation failed"
mkdir -p "${MINE}/frontend/.vite"; echo '{}' > "${MINE}/frontend/.vite/x.json"
git worktree remove "${MINE}" >/dev/null 2>&1 || true    # leave an orphan behind
if [ -d "${MINE}" ]; then
  "${WT}" --gc --clean >/dev/null 2>&1
  [ ! -e "${MINE}" ] && ok "provenance: our own orphan IS cleaned without --force" || no "provenance: did not clean our own orphan"
else
  ok "provenance: git removed it cleanly, nothing orphaned"
fi

# ── --remove refuses an arbitrary directory ─────────────────────────────────
# Previously any existing directory resolved as an "orphan" and was trashed, so
# a typo'd path was a data-loss event.
R="$(repo_or_die)"; cd "${R}"
mkdir -p "${ROOTDIR}/precious"; echo "important" > "${ROOTDIR}/precious/data.txt"
"${WT}" --remove "${ROOTDIR}/precious" >/dev/null 2>&1
[ -f "${ROOTDIR}/precious/data.txt" ] && ok "guard: refuses an arbitrary directory path" || no "guard: TRASHED an unrelated directory"

# ── --tmp worktrees are in scope for --gc ───────────────────────────────────
R="$(repo_or_die)"; cd "${R}"
TMPRES="${TMPDIR:-/tmp}/$(basename "${R}")-tmp-residue"
mkdir -p "${TMPRES}/frontend/.vite"; echo '{}' > "${TMPRES}/frontend/.vite/x.json"
out="$("${WT}" --gc 2>&1)"
if grep -q "$(basename "${TMPRES}")" <<<"${out}"; then ok "gc: scans TMPDIR, where --tmp worktrees live"
else no "gc: blind to --tmp residue: ${out}"; fi
scrub_sandbox "${TMPRES}"

# ── refuses to remove the main checkout ──────────────────────────────────────
# Stand in a WORKTREE and target the main checkout. Standing inside the main
# checkout itself means the "that is your own cwd" guard fires first, and the
# test passed even with the main-checkout guard deleted — it asserted the
# outcome (refused) without pinning which of two guards produced it. Standing
# outside the repo entirely fails earlier still ("not inside a git repository").
# A worktree is the one vantage point where this guard is the one that fires.
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b guard-vantage "${R}-guard-vantage" main
cd "${R}-guard-vantage"
out="$("${WT}" --remove "${R}" 2>&1)"; rc=$?
if [ "${rc}" -ne 0 ]; then ok "guard: refuses to remove the main checkout"
else no "guard: removed the main checkout"; fi
# Assert the specific REASON, not just the refusal.
case "${out}" in
  *"main checkout"*) ok "guard: refused FOR the main-checkout reason" ;;
  *) no "guard: refused, but not as the main checkout (got: ${out})" ;;
esac
cd "${R}"
[ -d "${R}/.git" ] && ok "guard: main checkout intact" || no "guard: main checkout damaged"

# ── uncommitted tracked changes block removal, --force overrides ─────────────
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-d "${R}-feat-d" main
echo 'edited' >> "${R}-feat-d/a.txt"                       # tracked + modified
if ! "${WT}" --remove "${R}-feat-d" >/dev/null 2>&1; then ok "guard: uncommitted changes block removal"
else no "guard: removed a worktree with uncommitted changes"; fi
[ -d "${R}-feat-d" ] && ok "guard: worktree survived the refusal" || no "guard: worktree was removed anyway"
"${WT}" --remove "${R}-feat-d" --force >/dev/null 2>&1
[ ! -e "${R}-feat-d" ] && ok "guard: --force overrides uncommitted changes" || no "guard: --force did not remove"

# ── unmerged commits: worktree goes, BRANCH is kept ──────────────────────────
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-e "${R}-feat-e" main
( cd "${R}-feat-e" && echo new > b.txt && git add -A && git -c user.email=t@t -c user.name=t commit -qm work )
"${WT}" --remove "${R}-feat-e" >/dev/null 2>&1
[ ! -e "${R}-feat-e" ] && ok "branch: unmerged worktree still removed" || no "branch: worktree not removed"
if git rev-parse --quiet --verify refs/heads/feat-e >/dev/null 2>&1; then
  ok "branch: unmerged branch KEPT (commits survive)"
else no "branch: deleted an unmerged branch and lost commits"; fi

# ── merged branch is cleaned up automatically ───────────────────────────────
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-f "${R}-feat-f" main
"${WT}" --remove "${R}-feat-f" >/dev/null 2>&1
if ! git rev-parse --quiet --verify refs/heads/feat-f >/dev/null 2>&1; then
  ok "branch: merged branch deleted automatically"
else no "branch: left a merged branch behind"; fi

# ── --dry-run touches nothing ───────────────────────────────────────────────
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-g "${R}-feat-g" main
"${WT}" --remove "${R}-feat-g" --dry-run >/dev/null 2>&1
[ -d "${R}-feat-g" ] && ok "dry-run: worktree untouched" || no "dry-run: removed the worktree"

# ── refuses to remove the directory you are standing in ─────────────────────
R="$(repo_or_die)"
git worktree add -q -b feat-h "${R}-feat-h" main
cd "${R}-feat-h" || exit 1
if ! "${WT}" --remove "${R}-feat-h" >/dev/null 2>&1; then ok "guard: refuses to remove your own cwd"
else no "guard: removed the cwd out from under itself"; fi
cd "${R}" || exit 1
[ -d "${R}-feat-h" ] && ok "guard: cwd worktree intact" || no "guard: cwd worktree destroyed"

# ── resolve by BRANCH NAME, not just path ───────────────────────────────────
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-i "${R}-feat-i" main
"${WT}" --remove feat-i >/dev/null 2>&1
[ ! -e "${R}-feat-i" ] && ok "resolve: --remove accepts a branch name" || no "resolve: branch name not resolved"

# ── live process blocks removal even with --force ───────────────────────────
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-j "${R}-feat-j" main
( cd "${R}-feat-j" && sleep 6 ) &
HOLDER=$!
sleep 0.5
"${WT}" --remove "${R}-feat-j" --force >/dev/null 2>&1
if [ -d "${R}-feat-j" ]; then ok "guard: live process blocks removal even under --force"
else no "guard: removed a worktree with a live process in it"; fi
kill "${HOLDER}" 2>/dev/null; wait "${HOLDER}" 2>/dev/null

# ── lsof missing: the process check cannot run, and must SAY so ─────────────
# Silence here would look identical to "nothing is running", which disarms the
# only guard against failure mode B. lsof lives outside /usr/bin and /bin, so a
# trimmed PATH removes it while leaving git available.
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-k "${R}-feat-k" main
out="$(PATH="${BINSTUB}:/usr/bin:/bin" "${WT}" --remove "${R}-feat-k" 2>&1)"
if grep -qi 'lsof is unavailable' <<<"${out}"; then
  ok "missing-tool: says the live-process check could not run"
else
  no "missing-tool: silently skipped the process check: ${out}"
fi
# "Could not check" must route to the REFUSING branch, not to "nothing running".
# Warning and proceeding anyway leaves the guard decorative.
[ -d "${R}-feat-k" ] && ok "missing-tool: REFUSES rather than removing unchecked" || no "missing-tool: removed without checking"
PATH="${BINSTUB}:/usr/bin:/bin" "${WT}" --remove "${R}-feat-k" --force >/dev/null 2>&1
[ ! -e "${R}-feat-k" ] && ok "missing-tool: --force accepts the unchecked risk explicitly" || no "missing-tool: --force did not proceed"

# ── a BROKEN lsof is as unchecked as a missing one ───────────────────────────
# Present-but-failing is the realistic case (denied process listing, sandbox).
# Piping lsof into awk hid it: pipefail returned 1, callers only knew about 2,
# and empty output read as "nothing is running".
R="$(repo_or_die)"; cd "${R}"
git worktree add -q -b feat-l "${R}-feat-l" main
printf '#!/bin/sh\nexit 1\n' > "${BINSTUB}/lsof"; chmod +x "${BINSTUB}/lsof"
out="$(PATH="${BINSTUB}:/usr/bin:/bin" "${WT}" --remove "${R}-feat-l" 2>&1)"
if [ -d "${R}-feat-l" ] && grep -qi 'could not be checked' <<<"${out}"; then
  ok "broken-tool: a failing lsof refuses too, not just a missing one"
else
  no "broken-tool: proceeded on a failed process scan: ${out}"
fi
mv "${BINSTUB}/lsof" "${BINSTUB}/lsof.disabled"   # rename, not delete: nothing to recover from

echo "--------------------------------------------"
printf 'PASS=%d  FAIL=%d\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
