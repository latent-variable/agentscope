#!/usr/bin/env bash
# Behavior tests for verify.sh --index-only, the memory/MEMORY.md gate.
#
# MEMORY.md is pasted into EVERY turn of EVERY agent, so its failure modes are
# paid forever and none of them announce themselves:
#   BLOAT      entries grow from hooks into summaries. `remember` has said "one
#              line each, no content" from the start, and agents complied with
#              the letter while writing 400-char lines — "one line" is true of
#              any length, so it constrains nothing. Hence a MEASURED bound.
#   INVISIBLE  a memory with no index entry is never found.
#   HUNTING    an index entry pointing at a deleted file sends an agent looking.
# Each defect is paired with a control, so a checker that flags everything
# cannot pass this suite.
set -uo pipefail
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

VERIFY="$(cd "$(dirname "$0")/.." && pwd)/bin/verify.sh"
[ -f "$VERIFY" ] || { echo "verify.sh not found at $VERIFY"; exit 1; }

SB="$(mktemp -d)"
# Recoverable teardown per canon: Trash, never an unbounded delete, and the guard
# stays so an empty or wrong variable cannot reach the delete at all.
trap '[ -n "${SB:-}" ] && [ -d "$SB" ] && case "$SB" in /*) [ -x /usr/bin/trash ] && /usr/bin/trash "$SB" 2>/dev/null;; esac' EXIT
mkdir -p "$SB/memory" "$SB/skills"
printf '# A\nbody\n' > "$SB/memory/alpha.md"
printf '# B\nbody\n' > "$SB/memory/beta.md"

idx(){ printf '%s\n' "$@" > "$SB/memory/MEMORY.md"; }
run(){ AGENTS_DIR="$SB" bash "$VERIFY" --index-only 2>&1; }

# --- CONTROL: a healthy index passes ----------------------------------------
idx "# Memory index" "" "- [Alpha](alpha.md), when you need alpha" "- [Beta](beta.md), when you need beta"
out="$(run)"; rc=$?
[ $rc -eq 0 ] && grep -q "index and files agree" <<<"$out" \
  && ok "control: a healthy index passes clean" || no "control: false positive (rc=$rc)"

# --- BLOAT ------------------------------------------------------------------
long="- [Alpha](alpha.md), $(printf 'x%.0s' $(seq 1 220))"
idx "# Memory index" "" "$long" "- [Beta](beta.md), when you need beta"
out="$(run)"; rc=$?
[ $rc -ne 0 ] && grep -q "index entry" <<<"$out" \
  && ok "an over-long entry is flagged with its length" || no "bloat not caught (rc=$rc)"

# A 199-char entry must NOT flag: the bound is a real edge, not a vibe.
edge="- [Alpha](alpha.md), $(printf 'x%.0s' $(seq 1 178))"
idx "# Memory index" "" "$edge" "- [Beta](beta.md), b"
[ ${#edge} -le 200 ] || { echo "  (fixture miscomputed: ${#edge})"; }
out="$(run)"; rc=$?
[ $rc -eq 0 ] && ok "an entry just under the bound (${#edge}) is NOT flagged" \
              || no "off-by-one: flagged a legal ${#edge}-char entry"

# --- INVISIBLE: a memory with no index entry --------------------------------
idx "# Memory index" "" "- [Alpha](alpha.md), when you need alpha"
out="$(run)"; rc=$?
[ $rc -ne 0 ] && grep -q "memory not indexed: beta.md" <<<"$out" \
  && ok "an unindexed memory is reported" || no "unindexed memory missed (rc=$rc)"

# --- HUNTING: an entry pointing at nothing ----------------------------------
idx "# Memory index" "" "- [Alpha](alpha.md), a" "- [Beta](beta.md), b" "- [Ghost](ghost.md), never written"
out="$(run)"; rc=$?
[ $rc -ne 0 ] && grep -q "missing file: ghost.md" <<<"$out" \
  && ok "an index entry with no file is reported" || no "dangling pointer missed (rc=$rc)"

# --- the bound is configurable, and honoured --------------------------------
idx "# Memory index" "" "- [Alpha](alpha.md), $(printf 'y%.0s' $(seq 1 100))" "- [Beta](beta.md), b"
CANON_INDEX_ENTRY_MAX=60 AGENTS_DIR="$SB" bash "$VERIFY" --index-only >/dev/null 2>&1 \
  && no "a tighter bound was ignored" || ok "CANON_INDEX_ENTRY_MAX tightens the bound"

# --- exit status is the gate ------------------------------------------------
idx "# Memory index" "" "- [Alpha](alpha.md), a" "- [Beta](beta.md), b"
AGENTS_DIR="$SB" bash "$VERIFY" --index-only >/dev/null 2>&1 \
  && ok "exit 0 on a clean index" || no "exit status wrong on a clean index"

echo "--------------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ $FAIL -eq 0 ]
