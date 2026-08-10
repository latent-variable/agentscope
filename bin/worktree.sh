#!/usr/bin/env bash
#
# Create a git worktree you can actually BUILD in.
#
# Agents sharing one working copy is the root cause of both production
# incidents on 2026-07-28:
#
#   1. Someone moved HEAD to a branch 11 commits behind while a deploy was
#      mid-build. It survived on timing alone.
#   2. Someone escaped to a worktree to avoid exactly that — and shipped a site
#      that could not authenticate, because a worktree does not carry
#      gitignored config. ~15 minutes of production down.
#
# The second one is why "just use a worktree" is not advice you can give
# safely. `git worktree add` gives you the tracked files and nothing else. Every
# gitignored build input — API keys, service-account JSON, .env files — stays
# behind in the original clone, and the tools that need them do not fail. Vite
# inlines `undefined` and exits 0. The build looks perfect and the product is
# broken.
#
# So this does the two things `git worktree add` does not: it copies the
# gitignored files a build actually needs, and it tells you what it copied.
#
# Teardown is the other half, and `git worktree remove` gets it wrong two ways.
# Both are reproduced in tests/worktree-remove.test.sh:
#
#   A. It REFUSES on any untracked file that is not ignored — a scratch note, a
#      probe script, a generated report. Exit 128, and the whole worktree
#      survives untouched. The agent sees an error it did not cause and moves on,
#      so the worktree lives forever and you clean it up by hand later.
#   B. Worse, it can report SUCCESS and still leave a directory behind. If any
#      process is still running in the worktree (a Vite dev server, a Firebase
#      emulator, a file watcher) it re-creates its cache the instant git finishes
#      deleting. git exits 0, de-registers the worktree, and a skeleton survives
#      that `git worktree list` no longer knows about and `git worktree prune`
#      will never touch — prune cleans metadata for missing directories, not
#      directories for missing metadata. Observed in the wild: a worktree left
#      holding frontend/.vite/deps after a Vite dev server outlived it.
#
# So --remove checks what git does not (live processes, unmerged commits,
# uncommitted work), removes, and then VERIFIES the directory is actually gone
# instead of trusting the exit code. --gc finds the orphans already on disk.
#
# usage-begin
#   worktree.sh <branch> [base]        create ./<repo>-<branch> off base (default: origin/HEAD)
#   worktree.sh <branch> --tmp         create it under the OS temp dir instead
#   worktree.sh --list                 list this repo's worktrees and their config status
#   worktree.sh --sync <path>          re-copy config into an existing worktree
#   worktree.sh --remove <path|branch> tear one down completely, then verify it is gone
#   worktree.sh --gc                   REPORT orphan worktree dirs + stale metadata
#   worktree.sh --gc --clean           and actually remove what it found
#
#   --force   with --remove: proceed despite uncommitted work, or when lsof is
#             unavailable. A DETECTED live process is never overridable.
#             With --gc: clean residue despite a stale shell sitting in it.
#   --dry-run with --remove: print what would happen, touch nothing (--gc is
#             report-only by default, so it needs no such flag)
#
# Deletions go to macOS Trash via `trash`, never `rm -rf` (recoverable, per canon).
# Run it from inside the repo you want a worktree of.
# usage-end
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

git rev-parse --git-dir >/dev/null 2>&1 || { err "Not inside a git repository."; exit 1; }

# ROOT is the repo's MAIN CHECKOUT, never "whichever worktree I am standing in".
#
# This used to be `git rev-parse --show-toplevel`, which returns the CURRENT
# worktree. Every ROOT comparison below then silently changed meaning the moment
# you ran the script from a worktree — and canon tells agents to work in
# worktrees, so that is the normal case, not the exotic one. Concretely, the
# "refusing to remove the main checkout" guard on line ~427 compared the target
# against the worktree, so it never fired, and:
#
#     cd <a worktree> && worktree.sh --remove main
#
# resolved `main` to the main checkout and trashed the whole thing — .git,
# tracked files, and with it every other worktree attached to that repo. It
# survived only because deletes go to Trash. Reproduced end to end; the guard
# that exists to prevent exactly this was unreachable from the one vantage point
# it mattered from.
#
# `git worktree list --porcelain` always lists the main worktree first, from any
# vantage point. --git-common-dir is the fallback: it points at the main
# checkout's .git even from inside a worktree.
ROOT="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
if [ -z "${ROOT}" ] || [ ! -d "${ROOT}" ]; then
  _common="$(git rev-parse --git-common-dir 2>/dev/null || echo '')"
  case "${_common}" in ''|/*) ;; *) _common="$(pwd -P)/${_common}" ;; esac
  if [ -n "${_common}" ] && [ -d "$(dirname "${_common}")" ]; then
    ROOT="$(cd "$(dirname "${_common}")" && pwd -P)"
  else
    ROOT="$(git rev-parse --show-toplevel)"
  fi
fi
ROOT="$(cd "${ROOT}" && pwd -P)"
cd "${ROOT}"
REPO="$(basename "${ROOT}")"

# Gitignored files a build or a local run needs.
#
# The named list below is the FLOOR. It stays because some inputs are not
# env-shaped and pattern matching would miss them.
#
# It is not sufficient on its own, and a real deploy proved it: the list did not
# name `functions/.env`, the file carrying a Cloud Functions service's entire
# runtime environment, so the script reported "No gitignored config found to
# copy" and a deploy from that worktree would have shipped the service with its
# environment missing. Silent, and on a green build. A list only protects repos
# somebody remembered to add, and the maintenance cost lands exactly when the
# stakes are highest: a repo that just grew a new secret.
#
# So the list is now combined with DISCOVERY (see discovered_config): any
# gitignored, env-shaped file in the repo, excluding build output and vendor
# directories. Discovery cannot go stale. Everything copied is printed, so it is
# visible rather than magic.
CONFIG_FILES=(
  frontend/.env.local
  frontend/.env.production
  frontend/.env.production.local
  functions/.env             # relay/functions runtime env; deploying without it wipes the service config
  functions/.secret.local
  agent/.env                 # ADK agent deploy env: the GEMINI_MODEL pin lives here (2026-07-18 outage)
  .env.local
  .env.production
  web/.env.production        # portal repo, where this failure happened first
  .firebaserc
)

# Discovery guards. Env-shaped names only, never inside build output or vendored
# trees, and never a large file (a stray dump or an accidental archive).
DISCOVER_SKIP_DIRS='(^|/)(node_modules|dist|build|out|\.next|\.nuxt|\.output|\.firebase|\.venv|venv|__pycache__|emulator-data|coverage|\.turbo|\.cache|\.git)(/|$)'
DISCOVER_NAMES='(^|/)(\.env|\.env\.[^/]+|[^/]*\.secret\.local|\.runtimeconfig\.json|[^/]*service-account[^/]*\.json|[^/]*-key\.json)$'
MAX_CONFIG_BYTES=262144

# Gitignored, env-shaped files this repo actually has. `git ls-files -o -i` lists
# only IGNORED files, so a tracked .env.template or .env.example never appears.
discovered_config() {
  git ls-files -o -i --exclude-standard 2>/dev/null \
    | grep -Ev "${DISCOVER_SKIP_DIRS}" \
    | grep -E "${DISCOVER_NAMES}" \
    || true
}

# The named floor plus discovery, de-duplicated, order-stable. One path per line.
effective_config_files() {
  { printf '%s\n' "${CONFIG_FILES[@]}"; discovered_config; } | awk 'NF && !seen[$0]++'
}

copy_config() {
  local dest="$1" copied=0 skipped_big=0 f size
  while IFS= read -r f; do
    if [ -f "${ROOT}/${f}" ]; then
      # Skip anything git actually tracks: the worktree already has it, and
      # copying would mask a real difference between the two trees.
      if git ls-files --error-unmatch "${f}" >/dev/null 2>&1; then
        continue
      fi
      size="$(wc -c < "${ROOT}/${f}" | tr -d ' ')"
      if [ "${size}" -gt "${MAX_CONFIG_BYTES}" ]; then
        warn "Skipped ${f} (${size} bytes, over ${MAX_CONFIG_BYTES}); copy it by hand if a build needs it."
        skipped_big=$((skipped_big + 1))
        continue
      fi
      mkdir -p "${dest}/$(dirname "${f}")"
      cp "${ROOT}/${f}" "${dest}/${f}"
      echo "         ${f}"
      copied=$((copied + 1))
    fi
  done <<EOF
$(effective_config_files)
EOF
  if [ "${copied}" -eq 0 ]; then
    warn "No gitignored config found to copy. That is expected for a repo that"
    warn "needs none. If a build here needs one, name it in CONFIG_FILES in"
    warn "$(basename "$0") (discovery already covers .env-shaped files)."
  else
    ok "Copied ${copied} config file(s) the worktree would not otherwise have."
  fi
}

# Report whether a worktree is safe to build in, without printing any values.
config_status() {
  local wt="$1" have=0 want=0 f
  while IFS= read -r f; do
    if [ -f "${ROOT}/${f}" ] && ! git ls-files --error-unmatch "${f}" >/dev/null 2>&1; then
      want=$((want + 1))
      [ -f "${wt}/${f}" ] && have=$((have + 1))
    fi
  done <<EOF
$(effective_config_files)
EOF
  if [ "${want}" -eq 0 ]; then
    echo "no config needed"
  elif [ "${have}" -eq "${want}" ]; then
    echo "config ok (${have}/${want})"
  else
    echo "MISSING CONFIG (${have}/${want}) — builds here will ship broken"
  fi
}

# ── Teardown ─────────────────────────────────────────────────────────────────

# Recoverable delete, per canon. Never rm -rf. If `trash` is missing we stop
# rather than silently escalating to an unrecoverable delete.
safe_delete() {
  local target="$1" out
  if command -v trash >/dev/null 2>&1; then
    # -v so the tool REPORTS where it went. macOS TCC blocks a terminal process
    # from listing ~/.Trash ("Operation not permitted"), so an operator checking
    # by hand sees an empty directory and reasonably concludes the file was
    # destroyed. Printing trash's own confirmation is the only cheap proof.
    out="$(trash -v "${target}" 2>&1)" || { err "trash failed on ${target}: ${out}"; return 1; }
    [ -n "${out}" ] && printf '         %s\n' "${out#\# }"
  else
    err "\`trash\` is not installed, and this script will not fall back to rm."
    err "Install it (brew install trash) or remove ${target} yourself."
    return 1
  fi
}

# PHYSICAL absolute path, symlinks resolved, target need not exist.
#
# `cd -P` matters and is not a nicety: on macOS /tmp and /var are symlinks into
# /private, and `git rev-parse --show-toplevel` always reports the resolved form.
# Comparing a caller's /var/... against git's /private/var/... is a string
# mismatch, which silently disarmed every guard below (main-checkout, own-cwd,
# live-process) when a repo lived under a symlinked path. Caught by the tests.
abspath() (            # subshell: the cd must never leak to the caller
  p="$1"
  case "${p}" in /*) ;; *) p="${PWD}/${p}" ;; esac
  d="$(dirname "${p}")"; b="$(basename "${p}")"
  if cd -P "${d}" 2>/dev/null; then printf '%s' "$(pwd -P)/${b}"
  else printf '%s' "${p}"; fi
)

registered_worktrees() {
  git worktree list --porcelain | awk '/^worktree /{print substr($0, 10)}'
}

is_registered() {
  local t="$1" w
  while IFS= read -r w; do [ "${w}" = "${t}" ] && return 0; done <<EOF
$(registered_worktrees)
EOF
  return 1
}

# PIDs whose current working directory is inside a path. This is failure mode B:
# a live process re-creates its cache after git deletes, so the removal "succeeds"
# and leaves a skeleton. Cheap (~0.15s) and worth it every time.
# Exit 0 = checked, PIDs (if any) on stdout. Exit 2 = COULD NOT CHECK.
# Those are different answers and the caller must treat them differently: an
# empty result from an unavailable checker is not evidence that nothing is
# running, and collapsing the two silently disarms the only guard against
# failure mode B. (Canon: guard the MISSING case, route the unknown to the
# refusing branch.)
procs_in() {
  local dir="$1" raw
  command -v lsof >/dev/null 2>&1 || return 2
  # A missing binary is not the only way this check fails to run. lsof can be
  # present and still return nothing useful (denied process listing, sandbox,
  # hardened runtime). Piping it straight into awk hid that: under pipefail the
  # pipeline returned 1, callers only recognised 2 as "unchecked", and an empty
  # result was read as "nothing is running" — the same missing-case bug one
  # level down, in the guard whose entire job is preventing failure mode B.
  #
  # lsof legitimately exits nonzero while still producing valid output (it warns
  # about processes it cannot stat), so status alone is not the signal. A whole-
  # system cwd listing that yields NOTHING is the real tell: that never happens
  # on a working checker.
  raw="$(lsof -a -d cwd -Fpn 2>/dev/null || true)"
  [ -n "${raw}" ] || return 2
  printf '%s\n' "${raw}" | awk -v d="${dir}" '
    /^p/ { pid = substr($0, 2) }
    /^n/ { path = substr($0, 2)
           if (path == d || index(path, d "/") == 1) print pid }
  ' | sort -u
}

# The branch checked out in a worktree, or empty for a detached HEAD.
worktree_branch() {
  git worktree list --porcelain | awk -v t="$1" '
    /^worktree /   { w = substr($0, 10) }
    /^branch /     { if (w == t) { sub(/^branch refs\/heads\//, ""); print; exit } }
  '
}

# ── Provenance ───────────────────────────────────────────────────────────────
#
# Structural tests (name prefix, no .git, all contents ignored) narrow the field
# but never PROVE a directory is ours. A sibling `<repo>-build` holding only
# node_modules and .env.local satisfies every one of them and is somebody's work.
# Heuristics that end in a delete need positive evidence, not the absence of
# counter-evidence.
#
# So creation records the path here, and --clean only removes directories that
# appear in it. The registry lives in the COMMON git dir, which survives the
# worktree being orphaned (its own .git is what disappears) and is shared by
# every worktree of the repo.
#
# Anything not listed (made by hand, or predating this) is still REPORTED, and
# still removable with an explicit --force. Discovery stays wide; deletion is
# what got narrow.
provenance_file() {
  local common
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "${common}" in /*) ;; *) common="${ROOT}/${common}" ;; esac
  printf '%s' "${common}/agents-worktrees"
}

# Identity is the PATH, deliberately, and not path+inode.
#
# Inode was the obvious hardening against a reused path and it is wrong here.
# Failure mode B — the case this whole command exists for — is a directory that
# git deleted and a live process immediately RE-CREATED. That recreated
# directory necessarily has a new inode, so an inode check refuses to clean
# exactly the orphan we are hunting. The test suite caught it instantly: test B
# went red the moment inode matching went in.
#
# The residual risk is a stale record authorizing a later, unrelated directory
# at the same path. It is bounded: the deletion goes to Trash, and prune_stale
# below drops any record whose path has vanished, so a path that goes away and
# comes back is not covered by the old record.
record_provenance() {
  local f; f="$(provenance_file)" || return 0
  printf '%s\n' "$1" >> "${f}" 2>/dev/null || true
}

has_provenance() {
  local f; f="$(provenance_file)" || return 1
  [ -f "${f}" ] || return 1
  grep -Fxq -- "$1" "${f}" 2>/dev/null
}

forget_provenance() {
  local f tmp; f="$(provenance_file)" || return 0
  [ -f "${f}" ] || return 0
  tmp="${f}.tmp.$$"
  grep -Fxv -- "$1" "${f}" > "${tmp}" 2>/dev/null || true
  mv "${tmp}" "${f}" 2>/dev/null || true
}

# Drop records whose directory no longer exists. Keeps the file from growing
# without bound, and shrinks the reuse window: a path that disappears loses its
# authorization before anything can be created there again.
#
# This MUTATES the registry, so it runs only under --clean. A plain `--gc` says
# report-only and has to mean it; rewriting shared state during a read-only
# report is its own defect, independent of what the rewrite does.
#
# The rewrite is a read-modify-write on a file that several agents in this repo
# may append to concurrently, so a record appended mid-flight can be lost. Left
# unguarded deliberately: losing a record only ever makes --clean MORE
# conservative, since an unrecorded orphan is reported and kept, never deleted.
# The race fails toward not deleting. A lock would add contention and a fresh
# failure mode to protect a direction that is already safe.
prune_stale_provenance() {
  local f tmp p; f="$(provenance_file)" || return 0
  [ -f "${f}" ] || return 0
  tmp="${f}.tmp.$$"
  : > "${tmp}"
  while IFS= read -r p; do
    [ -z "${p}" ] && continue
    [ -d "${p}" ] && printf '%s\n' "${p}" >> "${tmp}"
  done < "${f}"
  mv "${tmp}" "${f}" 2>/dev/null || true
}

# The two places worktree.sh is allowed to create a worktree, and therefore the
# only two places it is allowed to delete one from.
worktree_parents() {
  printf '%s\n' "$(dirname "${ROOT}")"
  local tmp; tmp="$(abspath "${TMPDIR:-/tmp}")"
  [ "${tmp}" = "$(dirname "${ROOT}")" ] || printf '%s\n' "${tmp}"
}

# Does this path look like residue THIS script could have produced? Name alone is
# not authorization to delete: a plain sibling folder called <repo>-notes matches
# a prefix glob perfectly. Require all of:
#   - sits directly in a directory we create worktrees in
#   - name is <repo>-<something>
#   - git does not know it as a worktree
#   - no .git entry (a real clone or live worktree has one)
#   - every file in it is one THIS REPO ignores. That is the load-bearing test:
#     residue survives precisely because git ignored those files. A directory
#     holding anything git would track is somebody's work, not our leftovers.
looks_like_residue() {
  local d="$1" parent ok=1 p rel
  [ -d "${d}" ] || return 1
  [ -e "${d}/.git" ] && return 1
  is_registered "${d}" && return 1
  ok=0
  while IFS= read -r parent; do
    [ "$(dirname "${d}")" = "${parent}" ] && { ok=1; break; }
  done <<EOF
$(worktree_parents)
EOF
  [ "${ok}" = "1" ] || return 1
  case "$(basename "${d}")" in "${REPO}"-*) ;; *) return 1 ;; esac
  # POSITIVE evidence required, and `! -type d` rather than `-type f`.
  #
  # Two holes closed here, both of which ended in "trash it". `-type f` matches
  # only regular files, so a directory holding nothing but symlinks (or sockets,
  # fifos) had an empty candidate list. And an EMPTY directory produced an empty
  # list too. Either way the loop body never executed and the function fell
  # through to `return 0` — residue by vacuous truth, on a path that deletes.
  # An unrecognisable directory is not evidence of residue; it is absence of
  # evidence, so it takes the refusing branch.
  local entries
  entries="$(find "${d}" ! -type d 2>/dev/null)"
  [ -n "${entries}" ] || return 1
  while IFS= read -r p; do
    [ -z "${p}" ] && continue
    rel="${p#"${d}/"}"
    git -C "${ROOT}" check-ignore -q -- "${rel}" 2>/dev/null || return 1
  done <<EOF
${entries}
EOF
  return 0
}

# Resolve a path OR a branch name to a worktree directory.
resolve_target() {
  local arg="$1" cand w b
  cand="$(abspath "${arg}")"
  if is_registered "${cand}"; then printf '%s' "${cand}"; return 0; fi
  # try as a branch name
  while IFS= read -r w; do
    [ "${w}" = "${ROOT}" ] && continue
    b="$(worktree_branch "${w}")"
    [ "${b}" = "${arg}" ] && { printf '%s' "${w}"; return 0; }
  done <<EOF
$(registered_worktrees)
EOF
  # An unregistered directory is accepted ONLY if it passes the residue test.
  # Without that, a typo or a stray path was accepted and trashed: everything
  # except the main checkout and the caller's cwd was fair game.
  looks_like_residue "${cand}" && { printf '%s' "${cand}"; return 0; }
  return 1
}

# Structural match plus provenance. Only this authorises an unattended delete.
is_our_residue() {
  looks_like_residue "$1" && has_provenance "$1"
}

remove_worktree() {
  local target="$1" force="$2" dry="$3"
  local branch dirty ahead pids p

  if [ "${target}" = "${ROOT}" ]; then
    err "${target} is the main checkout, not a worktree. Refusing."
    return 1
  fi
  case "$(pwd -P)/" in
    "${target}"/*)
      err "You are inside ${target}. Removing your own working directory is not safe."
      err "Run:  cd ${ROOT} && $(basename "$0") --remove ${target}"
      return 1 ;;
  esac
  if [ ! -d "${target}" ] && ! is_registered "${target}"; then
    err "Not a worktree of ${REPO} and not a directory: ${target}"
    return 1
  fi

  branch="$(worktree_branch "${target}")"
  info "Target:  ${target}"
  [ -n "${branch}" ] && info "Branch:  ${branch}"

  # ── Gates. Each one guards work that removal would destroy. ────────────────
  local blocked=0

  # 1. Live processes. The direct cause of failure mode B.
  # `|| pstat=$?` and not a bare `; pstat=$?`: under `set -e` a command
  # substitution that exits non-zero aborts the whole script at the assignment,
  # so the "could not check" branch below was never reached and the removal just
  # stopped dead with no message. The test still saw a surviving directory and
  # passed — a vacuous pass hiding a dead code path.
  local pstat=0
  pids="$(procs_in "${target}")" || pstat=$?
  if [ "${pstat}" = "2" ]; then
    # Could not check is not the same as nothing running. Refuse by default and
    # let --force carry the risk explicitly; a DETECTED process below is never
    # overridable, an unknown one is.
    if [ "${force}" = "1" ]; then
      warn "lsof unavailable, so live processes could NOT be checked; --force given, proceeding."
    else
      err "lsof is unavailable, so live processes in ${target} could not be checked."
      err "A dev server or emulator still running there would leave an orphan directory."
      err "Stop anything running there and re-run with --force, or install lsof."
      blocked=1
    fi
  elif [ -n "${pids}" ]; then
    err "Processes are still running in this worktree:"
    for p in ${pids}; do
      err "    pid ${p}  $(ps -o comm= -p "${p}" 2>/dev/null || echo '?')"
    done
    err "They will re-create files after git deletes them and leave an orphan directory."
    err "Stop them first. --force does NOT override this."
    blocked=1
  fi

  if is_registered "${target}"; then
    # 2. Uncommitted tracked changes.
    dirty="$(git -C "${target}" status --porcelain --untracked-files=no 2>/dev/null || true)"
    if [ -n "${dirty}" ]; then
      if [ "${force}" = "1" ]; then
        warn "Uncommitted changes present; --force given, proceeding:"
        printf '%s\n' "${dirty}" | sed 's/^/         /'
      else
        err "Uncommitted changes in ${target}:"
        printf '%s\n' "${dirty}" | sed 's/^/         /'
        err "Commit them, or re-run with --force to discard."
        blocked=1
      fi
    fi

    # 3. Commits that exist nowhere else. The branch ref survives removal, so
    #    this is a warning about deleting the BRANCH later, not about data loss
    #    from the removal itself.
    if [ -n "${branch}" ] && git rev-parse --quiet --verify "${BASE_REF}" >/dev/null 2>&1; then
      ahead="$(git rev-list --count "${BASE_REF}..${branch}" 2>/dev/null || echo 0)"
      if [ "${ahead:-0}" -gt 0 ]; then
        warn "Branch ${branch} has ${ahead} commit(s) not in ${BASE_REF}."
        warn "The worktree goes; the branch is KEPT so those commits survive."
      fi
    fi
  fi

  [ "${blocked}" = "1" ] && return 1

  if [ "${dry}" = "1" ]; then
    ok "[dry-run] would remove ${target}"
    [ -n "${branch}" ] && echo "         [dry-run] would delete branch ${branch} only if merged into ${BASE_REF}"
    return 0
  fi

  # ── Remove: TRASH FIRST, then let git clean up its own bookkeeping. ────────
  #
  # This order is the whole safety story and it used to be backwards. Calling
  # `git worktree remove --force` first hands the deletion to GIT, which unlinks
  # untracked and ignored files PERMANENTLY — no Trash, no undo. So the copied
  # .env, the scratch notes, the generated report were all destroyed outright,
  # while safe_delete only ever ran on whatever happened to survive. The script
  # advertised recoverable deletes and delivered rm.
  #
  # Trashing the directory first makes every byte recoverable from Finder, and
  # once the directory is gone `git worktree prune` clears the metadata by
  # itself. `git worktree remove` is never called, so git never deletes anything.
  # An UNREGISTERED target is only a heuristic match, so it needs provenance or
  # an explicit --force before we delete it. A registered worktree is git's own
  # answer and needs neither.
  if ! is_registered "${target}" && ! has_provenance "${target}" && [ "${force}" != "1" ]; then
    err "${target} matches the shape of residue but this script has no record of creating it."
    err "Remove it yourself, or re-run with --force if you are sure."
    return 1
  fi

  if [ -e "${target}" ]; then
    safe_delete "${target}" || return 1
  fi
  forget_provenance "${target}"

  git worktree prune

  if [ -e "${target}" ]; then
    err "STILL PRESENT after cleanup: ${target}"
    err "Something is re-creating it. Find the process and stop it."
    return 1
  fi
  if is_registered "${target}"; then
    err "Still registered with git after prune: ${target}"
    return 1
  fi

  # ── Branch: delete only when merged. Never silently drop commits. ──────────
  if [ -n "${branch}" ] && git rev-parse --quiet --verify "refs/heads/${branch}" >/dev/null 2>&1; then
    if git rev-parse --quiet --verify "${BASE_REF}" >/dev/null 2>&1 \
       && git merge-base --is-ancestor "${branch}" "${BASE_REF}" 2>/dev/null; then
      git branch -d "${branch}" >/dev/null 2>&1 && ok "Deleted merged branch ${branch}."
    else
      info "Kept branch ${branch} (not merged into ${BASE_REF}); delete it yourself when it lands."
    fi
  fi

  ok "Removed and verified gone: ${target}"
}

# Residue of this repo's worktrees, across BOTH places we create them: next to
# the clone, and under TMPDIR for `worktree.sh <branch> --tmp`. Scanning only the
# first meant a failed --tmp teardown was invisible to --gc forever.
# looks_like_residue carries the identity test; see it for why a name prefix
# alone is not enough to justify deleting a directory.
find_orphans() {
  local parent d
  while IFS= read -r parent; do
    [ -d "${parent}" ] || continue
    for d in "${parent}/${REPO}"-*; do
      looks_like_residue "${d}" && printf '%s\n' "${d}"
    done
  done <<EOF
$(worktree_parents)
EOF
}

# clean=1 actually deletes. Default is REPORT ONLY: matching a name pattern is
# discovery, not authorization, so --gc shows you what it found and you decide.
gc() {
  local clean="$1" force="${2:-0}" found=0 d pids rc=0 pstat
  echo ""
  info "Scanning ${REPO} for worktree residue..."
  [ "${clean}" = "1" ] || info "(report only; add --clean to remove what it finds)"
  [ "${clean}" = "1" ] && prune_stale_provenance

  local stale
  stale="$(git worktree prune --dry-run -v 2>/dev/null || true)"
  if [ -n "${stale}" ]; then
    found=1
    warn "Stale git metadata (worktree registered, directory gone):"
    printf '%s\n' "${stale}" | sed 's/^/         /'
    if [ "${clean}" = "1" ]; then
      git worktree prune && ok "Pruned stale metadata."
    else
      echo "         would run: git worktree prune"
    fi
  fi

  while IFS= read -r d; do
    [ -z "${d}" ] && continue
    found=1
    warn "Orphan directory (git does not know it exists): ${d}"
    find "${d}" -type f 2>/dev/null | head -10 | sed "s#${d}#         .#"
    pstat=0
    pids="$(procs_in "${d}")" || pstat=$?   # see remove_worktree: bare `; $?` dies under set -e
    if [ "${pstat}" = "2" ] && [ "${force}" != "1" ]; then
      err "         lsof unavailable, cannot confirm nothing is running here. Skipping."
      err "         Re-run with --force to clean it anyway."
      rc=1
      continue
    fi
    if [ -n "${pids}" ]; then
      # An orphan holds only ignored junk (git already forgot the worktree), so
      # a process sitting here is usually a stale shell an agent left behind
      # rather than something writing real work. Blocking is still the default,
      # but unlike --remove this one is overridable: otherwise one abandoned
      # shell keeps the residue on disk forever.
      warn "         Live processes inside:"
      for p in ${pids}; do
        warn "           pid ${p}  $(ps -o comm= -p "${p}" 2>/dev/null || echo 'gone')"
      done
      if [ "${force}" != "1" ]; then
        err "         Skipping. Stop them, or re-run: $(basename "$0") --gc --force"
        rc=1
        continue
      fi
      warn "         --force given; cleaning anyway (they will be left with a stale cwd)."
    fi
    # Provenance decides deletion; the structural match only decided reporting.
    if has_provenance "${d}"; then
      if [ "${clean}" = "1" ]; then
        safe_delete "${d}" && { forget_provenance "${d}"; ok "Trashed ${d} (recoverable from Finder)."; } || rc=1
      else
        echo "         created by this script; would trash it (recoverable), re-run with --clean"
      fi
    else
      echo "         NOT created by this script (no provenance record)."
      if [ "${clean}" = "1" ] && [ "${force}" = "1" ]; then
        warn "         --force given; trashing it anyway."
        safe_delete "${d}" || rc=1
      else
        echo "         left alone. Remove it yourself, or: $(basename "$0") --gc --clean --force"
        rc=1
      fi
    fi
  done <<EOF
$(find_orphans)
EOF

  if [ "${found}" = "0" ]; then
    ok "No residue. Every worktree directory and every bit of metadata agrees."
  fi
  echo ""
  return "${rc}"
}

BASE_REF="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo main)"

case "${1:-}" in
  --list)
    echo ""
    git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
      [ "${wt}" = "${ROOT}" ] && { echo "  ${wt}  (main checkout)"; continue; }
      echo "  ${wt}  [$(config_status "${wt}")]"
    done
    echo ""
    exit 0
    ;;
  --sync)
    DEST="${2:?usage: worktree.sh --sync <path>}"
    [ -d "${DEST}" ] || { err "No such worktree: ${DEST}"; exit 1; }
    info "Syncing config into ${DEST}"
    copy_config "${DEST}"
    exit 0
    ;;
  --remove | --rm)
    shift
    FORCE=0; DRY=0; ARG=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --force)   FORCE=1 ;;
        --dry-run) DRY=1 ;;
        -*)        err "Unknown flag for --remove: $1"; exit 1 ;;
        *)         ARG="$1" ;;
      esac
      shift
    done
    [ -n "${ARG}" ] || { err "usage: worktree.sh --remove <path|branch> [--force] [--dry-run]"; exit 1; }
    TARGET="$(resolve_target "${ARG}")" || { err "No worktree, branch or directory matching: ${ARG}"; exit 1; }
    remove_worktree "${TARGET}" "${FORCE}" "${DRY}"
    exit $?
    ;;
  --gc)
    shift
    CLEAN=0; FORCE=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --clean)   CLEAN=1 ;;
        --dry-run) CLEAN=0 ;;   # the default; accepted so the habit is harmless
        --force)   FORCE=1 ;;
        *)         err "Unknown flag for --gc: $1"; exit 1 ;;
      esac
      shift
    done
    gc "${CLEAN}" "${FORCE}"
    exit $?
    ;;
  "" | -h | --help)
    awk '/^# usage-begin$/{f=1;next} /^# usage-end$/{exit} f' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

BRANCH="$1"
BASE="${2:-}"
if [ -z "${BASE}" ] || [ "${BASE}" = "--tmp" ]; then
  BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
fi

if [ "${2:-}" = "--tmp" ] || [ "${3:-}" = "--tmp" ]; then
  DEST="${TMPDIR:-/tmp}/${REPO}-${BRANCH//\//-}"
else
  DEST="$(dirname "${ROOT}")/${REPO}-${BRANCH//\//-}"
fi

[ -e "${DEST}" ] && { err "${DEST} already exists."; exit 1; }

info "Fetching origin..."
git fetch --quiet origin || warn "Could not reach origin; basing on the local ref."

info "Creating worktree at ${DEST}"
info "  branch ${BRANCH} off ${BASE}"
git worktree add -b "${BRANCH}" "${DEST}" "${BASE}"
record_provenance "$(abspath "${DEST}")"

echo ""
info "Copying gitignored config (the step 'git worktree add' does not do):"
copy_config "${DEST}"

echo ""
ok "Ready:  cd ${DEST}"
echo ""
echo "  This worktree has its own HEAD, so nobody else's checkout can move it"
echo "  underneath you, and it carries the config a build needs."
echo ""
echo "  Config is COPIED, not linked — rotate a key in the main checkout and"
echo "  re-run:  worktree.sh --sync ${DEST}"
echo ""
