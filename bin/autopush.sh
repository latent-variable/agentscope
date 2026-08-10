#!/usr/bin/env bash
# Optional cadence backup for ~/.agents. Wire it to a scheduler (launchd, cron,
# systemd timer) so canon edits get backed up without you remembering to push.
# Quiet, idempotent, and does nothing when there is nothing to ship.
#
# ── What this is allowed to do, and why it is narrow ─────────────────────────
#
# This is a BACKUP, and it used to behave like a PUBLISHER. It ran `git add -A`
# on whatever was dirty, committed it under a generated message, and pushed to
# main. Two things go wrong with that, and only one of them is theoretical.
#
#   1. It publishes unreviewed CODE. A daemon that commits every 30 minutes
#      makes "code goes branch -> PR -> review" impossible in this repo, so the
#      canon contradicts itself and the daemon always wins. It once swept a
#      brand-new bin/worktree.sh — a tool that deletes directories — onto main
#      under a meaningless message, minutes after it was written.
#   2. It commits onto whatever branch is checked out. An agent branching here
#      to follow the review cycle finds its half-finished work committed and
#      pushed underneath it.
#
# The fix is SCOPE, not cadence. Running it at midnight instead sweeps exactly
# the same wrong things, just later, while making the backup guarantee worse.
# What a daemon is genuinely good at is catching an append-only fact somebody
# forgot to commit, and that is all it has ever actually done in practice.
#
# So now:
#   - It stands down entirely unless HEAD is the default branch.
#   - It only auto-COMMITS the append-only surface (memory/, generated caches).
#   - Anything else dirty is LOGGED and left alone, for a human or an agent to
#     commit with a real message. Never silently swept.
#   - It skips the rebase while such work is present, so --autostash can never
#     move an agent's in-progress edits underneath it.
#   - It still pushes commits somebody made deliberately. That is pure backup.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

A="${AGENTS_DIR:-$HOME/.agents}"
cd "$A" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
git remote get-url origin >/dev/null 2>&1 || exit 0

ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "[$(ts)] $*"; }

# Heartbeat: overwrite each run (no growth) so cadence is observable even on no-ops.
mkdir -p "$A/backups" 2>/dev/null || true
echo "[$(ts)] tick" > "$A/backups/last-run" 2>/dev/null || true

# Paths this daemon may commit on its own. Append-only facts and generated
# caches: self-describing, low-risk, and exactly what agents forget to commit.
# Deliberately NOT here: AGENTS.md, skills/, bin/, tests/, README. Those carry
# rationale a generated message cannot express, and bin/ carries executable code.
AUTO_RE='^(memory/|trello-boards\.json$)'

DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
[ -n "${DEFAULT_BRANCH}" ] || DEFAULT_BRANCH=main
BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo DETACHED)"

# ── Guard 1: only ever act on the default branch. ────────────────────────────
# An agent following the review cycle in this repo works on a branch. Touching
# it would commit half-finished work and push it. Stand down instead.
if [ "${BRANCH}" != "${DEFAULT_BRANCH}" ]; then
  log "on '${BRANCH}' (not ${DEFAULT_BRANCH}) — standing down, someone is working"
  exit 0
fi

# ── Split the dirty tree: what we may commit vs what a human must. ───────────
dirty="$(git status --porcelain 2>/dev/null)"
auto_paths=(); held_paths=()
while IFS= read -r line; do
  [ -z "${line}" ] && continue
  p="${line:3}"
  p="${p##* -> }"                       # renames: keep the destination
  p="${p%\"}"; p="${p#\"}"              # git quotes paths containing odd characters
  if [[ "${p}" =~ ${AUTO_RE} ]]; then auto_paths+=("${p}"); else held_paths+=("${p}"); fi
done <<< "${dirty}"

# ── Guard 2: never sweep anything outside the append-only surface. ───────────
if [ "${#held_paths[@]}" -gt 0 ]; then
  log "HOLDING ${#held_paths[@]} uncommitted path(s) — not mine to commit:"
  for p in "${held_paths[@]}"; do log "    ${p}"; done
  log "    commit them with a real message (code goes through the review cycle)"
fi

# ── Commit only the append-only surface, and name what went in. ──────────────
if [ "${#auto_paths[@]}" -gt 0 ]; then
  if git add -- "${auto_paths[@]}" 2>/dev/null; then
    summary="$(printf '%s, ' "${auto_paths[@]}" | sed 's/, $//')"
    [ "${#summary}" -gt 120 ] && summary="${#auto_paths[@]} files"
    # --only, not a bare commit. A bare `git commit` ships the WHOLE INDEX, so
    # any code an agent had already STAGED would ride along with a memory file
    # and reach the default branch under an "auto:" message — the exact bypass
    # this rescope exists to prevent. Adding the allowlisted paths is not enough;
    # the commit itself has to be pathspec-scoped.
    if git commit --only -q -m "auto: back up ${summary}" -- "${auto_paths[@]}"; then
      log "committed ${#auto_paths[@]} append-only path(s): ${summary}"
    else
      log "commit failed; leaving the tree as-is"
      # Scoped reset. A bare `git reset` would unstage work another agent staged
      # deliberately, which is exactly the state we just declined to touch.
      git reset -q -- "${auto_paths[@]}" 2>/dev/null || true
    fi
  else
    log "git add failed; leaving the tree as-is"
  fi
fi

# ── Reconcile + push. ────────────────────────────────────────────────────────
git fetch -q origin 2>/dev/null || { log "fetch failed (offline?)"; exit 0; }

# Guard 3: --autostash would stash and reapply an agent's in-progress edits
# around a rebase. Never do that while work we deliberately declined to commit
# is sitting in the tree. Push-only is the honest fallback.
# Re-read status RIGHT HERE, not from the scan at the top. Between the two sits
# a commit and a network fetch, which is plenty of time for an agent to start
# editing or stage something. Deciding on a stale snapshot means autostash could
# stash and reapply work that did not exist when we looked, and a conflict on
# reapply displaces it. The check has to be adjacent to the thing it guards.
dirty_now="$(git status --porcelain 2>/dev/null)"
if [ -z "${dirty_now}" ]; then
  git pull -q --rebase --autostash 2>/dev/null || { log "rebase conflict — left for manual fix"; exit 0; }
else
  log "skipping rebase, uncommitted work present at rebase time"
fi

ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
if [ "${ahead:-0}" -gt 0 ]; then
  if git push -q 2>/dev/null; then log "pushed ${ahead} commit(s)"; else log "push failed (rebase needed?)"; fi
fi
