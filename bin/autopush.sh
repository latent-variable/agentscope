#!/usr/bin/env bash
# Optional cadence backup for ~/.agents: commit + push any pending canon change, no-op when clean.
# Wire it to a scheduler (cron / launchd / systemd timer) so canon edits get backed up without manual pushes.
# Safe to run anytime. Pulls --rebase first to avoid diverging from the remote.
set -uo pipefail

AGENTS="$HOME/.agents"
cd "$AGENTS" 2>/dev/null || { echo "no $AGENTS"; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo — nothing to push"; exit 0; }
git remote get-url origin >/dev/null 2>&1 || { echo "no origin remote — set one to enable backup"; exit 0; }

# Bring in remote changes first (no-op if up to date).
git fetch -q origin 2>/dev/null || true
git pull -q --rebase --autostash 2>/dev/null || true

if [ -z "$(git status --porcelain)" ]; then
  # Clean tree; still push if we're ahead (e.g. an earlier offline commit).
  [ "$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)" -gt 0 ] && git push -q origin HEAD 2>/dev/null || true
  exit 0
fi

git add -A
git commit -q -m "chore: autopush canon $(date +%Y-%m-%dT%H:%M:%S)" 2>/dev/null || true
git push -q origin HEAD 2>/dev/null || echo "autopush: commit made, push failed (will retry next run)"
