#!/usr/bin/env bash
# Run every portable test suite in this repo.
#
# These test the tools that keep the shared brain honest: the drift detector, the
# always-on context meter, and the duplication scanner. Everything runs against
# throwaway copies under $TMPDIR; your real canon is never touched.
#
#   ./tests/run-tests.sh            # all suites
#   ./tests/run-tests.sh canon      # one suite, by name fragment
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
FILTER="${1:-}"

# Every suite resolves its own tool from its checkout, so a suite never silently
# tests the copy installed at ~/.agents instead of the one in this working tree.

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
