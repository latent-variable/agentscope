#!/usr/bin/env bash
# Behavior tests for verify.sh --links-only, the memory [[cross-link]] check.
#
# This check has TWO silent failure directions and both matter:
#   too NARROW  a broken pointer stays invisible, an agent hunts for a memory
#               that is one separator away, and gives up. That is the bug the
#               check was written for (19 live cases on 2026-08-17).
#   too WIDE    it flags the deliberate see-also links canon licenses ("link
#               liberally; a [[slug]] with no file yet is fine"). A checker that
#               red-boards correct prose gets ignored, and then the narrow
#               failures ride along behind it.
# So every planted defect is paired with a planted NON-defect. A run where only
# the first kind fires proves nothing.
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

mkdir -p "$SB/memory" "$SB/skills/example-workflow"
: > "$SB/skills/example-workflow/SKILL.md"
cat > "$SB/memory/real_target.md" <<'EOF'
# Real target
A memory that exists.
EOF
cat > "$SB/memory/another-target.md" <<'EOF'
# Another target
A memory that exists, named with hyphens.
EOF

run(){ AGENTS_DIR="$SB" bash "$VERIFY" --links-only 2>&1; }
body(){ printf '%s\n' "$1" > "$SB/memory/subject.md"; }

# --- CONTROL: a clean board must actually come back clean -------------------
# Without this the whole suite could pass against a check that flags everything.
body '# Subject
Points at [[real_target]] and [[another-target]]. Both exist.'
out="$(run)"; rc=$?
if [ $rc -eq 0 ] && grep -q 'ok    every load-bearing' <<<"$out"; then
  ok "control: valid links produce a clean board (exit 0)"
else
  no "control: false positive on valid links (rc=$rc)"
fi

# --- CONTROL: the see-also licence must survive -----------------------------
# Canon explicitly permits these. If this fires, the check is unusable.
body '# Subject
The rule itself is stated here in full.

Related: [[not_written_yet]], [[also_not_written]].'
out="$(run)"; rc=$?
if [ $rc -eq 0 ]; then
  ok "control: dangling see-also link on a Related: line is NOT flagged"
else
  no "control: flagged a see-also link canon licenses"
fi

body '# Subject
See [[nothing_here]], [[nor_here]].'
out="$(run)"; rc=$?
if [ $rc -eq 0 ]; then
  ok "control: a line that is only links is NOT flagged"
else
  no "control: flagged a bare see-also line"
fi

# --- CONTROL: syntax placeholders are not pointers --------------------------
body '# Subject
Link related memories with `[[their-slug]]`, e.g. `[[slug]]`.'
out="$(run)"; rc=$?
if [ $rc -eq 0 ]; then
  ok "control: [[slug]]/[[their-slug]] placeholders are NOT flagged"
else
  no "control: flagged a syntax placeholder"
fi

# --- DEFECT: broken pointer, target exists under another separator ----------
body '# Subject
Full framing: [[real-target]].'
out="$(run)"; rc=$?
if [ $rc -ne 0 ] && grep -q 'broken pointer, the memory is real_target.md' <<<"$out"; then
  ok "detects broken pointer (hyphen link, underscore file) and names the target"
else
  no "missed broken pointer real-target -> real_target"
fi

body '# Subject
Full framing: [[another_target]].'
out="$(run)"; rc=$?
if [ $rc -ne 0 ] && grep -q 'the memory is another-target.md' <<<"$out"; then
  ok "detects broken pointer in the other direction (underscore link, hyphen file)"
else
  no "missed broken pointer another_target -> another-target"
fi

# A broken pointer is a defect even in see-also position: the target EXISTS, so
# this is a typo, not the deliberate "not written yet" case the licence covers.
body '# Subject
Related: [[real-target]].'
out="$(run)"; rc=$?
if [ $rc -ne 0 ] && grep -q 'broken pointer' <<<"$out"; then
  ok "a broken pointer is flagged even on a Related: line (target exists)"
else
  no "see-also licence wrongly swallowed a typo whose target exists"
fi

# --- DEFECT: the name is a skill, not a memory ------------------------------
body '# Subject
Testing follows the bar from [[example-workflow]].'
out="$(run)"; rc=$?
if [ $rc -ne 0 ] && grep -q 'is a SKILL' <<<"$out"; then
  ok "detects a skill referenced with memory [[…]] syntax"
else
  no "missed a skill name in [[…]] syntax"
fi

# --- DEFECT: load-bearing dangle --------------------------------------------
body '# Subject
App Check is ENFORCING on the relay (see [[rollout_state_doc]]), so a scripted
turn is blocked.'
out="$(run)"; rc=$?
if [ $rc -ne 0 ] && grep -q 'cited as evidence but no such memory' <<<"$out"; then
  ok "detects a dangling link cited mid-sentence as evidence"
else
  no "missed a load-bearing dangling link"
fi

# The distinction is POSITION, not the name. Same missing target, see-also
# position, must not fire — this is what separates the two rules.
body '# Subject
The fact is stated here.

Related: [[rollout_state_doc]].'
out="$(run)"; rc=$?
if [ $rc -eq 0 ]; then
  ok "same missing target in see-also position is NOT flagged (position, not name)"
else
  no "check keys on the name rather than the position"
fi

# --- exit status is the gate, not just the wording --------------------------
body '# Subject
Evidence: [[definitely_missing_thing]].'
if AGENTS_DIR="$SB" bash "$VERIFY" --links-only >/dev/null 2>&1; then
  no "exit status stayed 0 on a real defect — the gate would never block"
else
  ok "exit status is 1 on a real defect (the gate actually gates)"
fi

# --- a label must not exempt a LATER load-bearing link on the same line ----
# Round-2 finding: keying on "a Related: marker appears earlier in the line"
# exempts every link after it, including the one that makes a promise.
body '# Subject
Related: [[not_written_yet]]; evidence is [[missing_target]].'
out="$(run)"; rc=$?
if [ $rc -ne 0 ] && grep -q 'missing_target' <<<"$out"; then
  ok "a load-bearing link AFTER a Related: label is still flagged"
else
  no "Related: label suppressed a later load-bearing link (rc=$rc)"
fi
# ...and the see-also link on that same line must NOT be flagged.
if grep -q 'not_written_yet' <<<"$out"; then
  no "over-corrected: flagged the genuine see-also link on the same line"
else
  ok "the genuine see-also link on that line is still exempt"
fi

# A ONE-word load-bearing clause is still prose. Counting words let this
# through; only real list connectors keep a run a list.
body '# Subject
Related: [[not_written_yet]]; evidence [[missing_target]].'
out="$(run)"; rc=$?
if [ $rc -ne 0 ] && grep -q 'missing_target' <<<"$out"; then
  ok "a ONE-word clause after a label does not exempt the next link"
else
  no "one-word clause slipped through (rc=$rc)"
fi

# ...but a genuine connector must still hold the list together.
body '# Subject
See [[not_written_yet]] and [[also_missing]].'
out="$(run)"; rc=$?
[ $rc -eq 0 ] && ok "a real connector (and) keeps the list exempt" \
              || no "over-corrected: 'and' broke a see-also list"

# The licence must survive on a LONG prose line ending in a Related: list. The
# reviewer's suggested fix (require ONLY_LINKS on the whole line) breaks this,
# which is why it was implemented as a trailing-run test instead.
body '# Subject
The rule is stated here in full and at some length, with detail. Related: [[not_written_yet]], [[also_missing]].'
out="$(run)"; rc=$?
if [ $rc -eq 0 ]; then
  ok "trailing Related: list on a long prose line is still exempt"
else
  no "over-corrected: flagged a trailing see-also list on a prose line"
fi

# A short residue is normal phrasing, not prose: `Related: [[x]] pattern.`
body '# Subject
Related: [[not_written_yet]] pattern.'
out="$(run)"; rc=$?
[ $rc -eq 0 ] && ok "short trailing residue still reads as see-also" \
              || no "over-corrected on 'Related: [[x]] pattern.'"

# --- the checker must FAIL CLOSED when it cannot run -----------------------
# A silent skip makes the whole verifier exit 0 having checked nothing, which is
# the exact failure this tool exists to catch. Simulated by putting a PATH in
# front that has no python3.
body '# Subject
Points at [[real_target]].'
FAKEBIN="$SB/.nopy"; mkdir -p "$FAKEBIN"
for c in bash grep sed awk git command; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$FAKEBIN/$c" 2>/dev/null
done
out="$(PATH="$FAKEBIN" AGENTS_DIR="$SB" bash "$VERIFY" --links-only 2>&1)"; rc=$?
if [ $rc -ne 0 ] && grep -q 'python3 unavailable' <<<"$out"; then
  ok "fails CLOSED when python3 is missing (drift, not a clean board)"
else
  no "fails OPEN without python3 — verifier would report clean having checked nothing (rc=$rc)"
fi

echo "--------------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ $FAIL -eq 0 ]
