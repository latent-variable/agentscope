#!/usr/bin/env bash
# Run every portable test suite in this repo.
#
# These test the two tools that can DESTROY something: worktree.sh (deletes
# directories) and autopush.sh (commits and pushes on its own). Everything runs
# against throwaway repos under $TMPDIR; your real canon is never touched.
#
#   ./tests/run-tests.sh          # all suites
#   ./tests/run-tests.sh worktree # one suite, by name fragment
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
FILTER="${1:-}"

export WT_SCRIPT="$ROOT/bin/worktree.sh"
export AUTOPUSH_SCRIPT="$ROOT/bin/autopush.sh"

TOTAL_PASS=0; TOTAL_FAIL=0; RAN=0

for suite in "$HERE"/*.test.sh; do
  [ -f "$suite" ] || continue
  name="$(basename "$suite" .test.sh)"
  [ -n "$FILTER" ] && case "$name" in *"$FILTER"*) ;; *) continue;; esac

  RAN=$((RAN+1))
  out="$(bash "$suite" 2>&1)"; echo "$out"
  # Each suite prints its own "PASS=n  FAIL=n" tally; roll them up.
  p="$(printf '%s' "$out" | sed -n 's/.*PASS=\([0-9]*\).*/\1/p' | tail -1)"
  f="$(printf '%s' "$out" | sed -n 's/.*FAIL=\([0-9]*\).*/\1/p' | tail -1)"
  TOTAL_PASS=$((TOTAL_PASS + ${p:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${f:-0}))
done

if [ "$RAN" -eq 0 ]; then echo "no suites matched '${FILTER}'"; exit 1; fi

echo "============================================"
printf 'TOTAL  PASS=%d  FAIL=%d  (%d suites)\n' "$TOTAL_PASS" "$TOTAL_FAIL" "$RAN"
[ "$TOTAL_FAIL" -eq 0 ] || exit 1
