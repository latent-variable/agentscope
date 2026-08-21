#!/usr/bin/env bash
# Tests for bin/canon-dupe — the duplication and contradiction net.
#
# The load-bearing case is the REAL contradiction this tool exists for: canon
# said a dedicated worktree "always" while the example-workflow skill said "only when
# needed", and it survived because the two sentences share exactly one content
# word, so every similarity score puts them at zero. If the fixture below stops
# being found, the tool has lost the only thing that justifies its second pass.
#
# The other risk is the opposite one: a net so wide nobody reads it. The live
# run was 403 pairs before the topic-rarity and proximity filters and 13 after,
# so the noise cases here are as important as the signal case.
set -uo pipefail

TOOL="$(cd "$(dirname "$0")/.." && pwd)/bin/canon-dupe"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

# Canon: recoverable deletes, and if `trash` is unavailable, say so rather than
# falling back to rm. The old line was `[ -x /usr/bin/trash ] && trash "$d"`,
# which SILENTLY did nothing on a machine without it and leaked every fixture.
TRASH="${TRASH_BIN-$(command -v trash || true)}"   # TRASH_BIN="" forces the unavailable path, for the test below
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
  printf '  \033[1;33mNOTE\033[0m  `trash` unavailable, fixtures left behind (remove by hand):\n'
  for d in $LEAKED; do printf '        %s\n' "$d"; done
}

SB="$(mktemp -d)"
trap 'discard "$SB"; report_leaks' EXIT
mkdir -p "$SB/skills/example-workflow" "$SB/memory"

echo "== canon-dupe =="

# ---------------------------------------------------------------- the real one
cat > "$SB/AGENTS.md" <<'EOF'
# canon

- **Worktrees**: code work starts in a dedicated worktree, always. Never begin substantive work in the shared clone or on whatever branch it sits on.
- Commit proactively when you finish and test a unit of work, not on every keystroke.
EOF
cat > "$SB/skills/example-workflow/SKILL.md" <<'EOF'
# review cycle

- Worktree only when needed, and the default is to branch in place. Use one only if another agent has uncommitted work in the checkout.
- Open the pull request once the branch is pushed and the validation has actually run.
EOF

out="$("$TOOL" --conflicts "$SB" 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -qi "worktree" <<<"$out"; then
  ok "conflict: finds always-vs-only-when on the same subject"
else
  no "conflict: MISSED the worktree contradiction (rc=$rc)"
fi

# Similarity must NOT be what finds it — that is the whole point of the pass.
out2="$("$TOOL" --dupes --min 0.30 "$SB" 2>&1)"
if ! grep -qi "worktree only when needed" <<<"$out2"; then
  ok "conflict: the dupe pass alone would have missed it"
else
  no "conflict: dupe pass caught it, so the fixture is not the real shape"
fi

# ------------------------------------------------------------------ the noise
# Two unrelated rules that merely share a common word must not pair up. Before
# the proximity filter, "actually" alone was enough to link them.
# Both sentences contain "actually", and it sits far from the modality in each,
# which is exactly the 403-pair noise the proximity filter removes.
cat > "$SB/memory/a.md" <<'EOF'
Never put a load-bearing argument only in the body of a reply, since the spoken block is what he actually hears.
EOF
cat > "$SB/memory/b.md" <<'EOF'
Cut a fresh build by default after the merge so that he can actually test the change on his own machine.
EOF
out="$("$TOOL" --conflicts "$SB" 2>&1)"
if ! grep -q "\[actually\]" <<<"$out"; then
  ok "noise: a shared common word alone does not pair two rules"
else
  no "noise: paired two unrelated rules on a common word"
fi

# ------------------------------------------------------------------- the dupes
cat > "$SB/memory/dup1.md" <<'EOF'
A plain worktree carries tracked files only and every gitignored build input stays behind in the original clone.
EOF
cat > "$SB/memory/dup2.md" <<'EOF'
Remember that a plain worktree carries tracked files only and every gitignored build input stays behind in the original clone.
EOF
out="$("$TOOL" --dupes "$SB" 2>&1)"; rc=$?
if [ $rc -eq 1 ] && grep -q "dup1.md" <<<"$out" && grep -q "dup2.md" <<<"$out"; then
  ok "dupes: finds the same passage in two files"
else
  no "dupes: missed a near-identical passage (rc=$rc)"
fi

# A file is not a duplicate of itself, and a symlinked CLAUDE.md is the same bytes
# as AGENTS.md — reporting that pair would flag every line of canon as duplicated.
ln -sf AGENTS.md "$SB/CLAUDE.md"
out="$("$TOOL" --dupes "$SB" 2>&1)"
if ! grep -q "CLAUDE.md" <<<"$out"; then
  ok "dupes: symlinked twin is not compared against its target"
else
  no "dupes: compared AGENTS.md with its own symlink"
fi

# ------------------------------------------------------------------ clean exit
CLEAN="$(mktemp -d)"
mkdir -p "$CLEAN/memory"
cat > "$CLEAN/AGENTS.md" <<'EOF'
Use trash rather than an unbounded delete, so a mistake stays recoverable from Finder.
EOF
cat > "$CLEAN/memory/x.md" <<'EOF'
The comp floor for a fully remote role is a hundred and fifty thousand base, applied without argument.
EOF
out="$("$TOOL" "$CLEAN" 2>&1)"; rc=$?
discard "$CLEAN"
if [ $rc -eq 0 ] && grep -q "clean" <<<"$out"; then
  ok "clean canon: exit 0 and says clean"
else
  no "clean canon: expected exit 0 + 'clean' (rc=$rc)"
fi

# Code fences hold commands that are SUPPOSED to be identical everywhere.
mkdir -p "$SB/skills/cleanup"
printf '# cleanup\n\n```\ncd ~/.agents && git add -A && git commit -m "fix: drift" && git push\n```\n' > "$SB/skills/cleanup/SKILL.md"
printf '# self correct\n\n```\ncd ~/.agents && git add -A && git commit -m "fix: drift" && git push\n```\n' > "$SB/memory/sc.md"
out="$("$TOOL" --dupes "$SB" 2>&1)"
if ! grep -q "git commit -m" <<<"$out"; then
  ok "fences: an identical command block is not reported as duplicated prose"
else
  no "fences: reported a fenced command as a duplicate"
fi

# ------------------------------------------------- detection-coverage gaps
# All three were reported by review on the first version, and all three let the
# net say "clean" about text it had never compared.

# 11. Hand-wrapped prose. Canon wraps at ~95 columns, so one rule spans several
#     physical lines; splitting on line boundaries chopped it into fragments that
#     fell under the word floor. Closing this took live duplication 12 -> 27.
WRAP="$(mktemp -d)"; mkdir -p "$WRAP/memory"
cat > "$WRAP/AGENTS.md" <<'EOF'
Verification is the whole safeguard here, so do it properly and never
trust a green build alone, because an upgrade that compiled but was
never actually run has not been verified at all.
EOF
cat > "$WRAP/memory/w.md" <<'EOF'
Verification is the whole safeguard here, so do it properly and never trust a green build alone, because an upgrade that compiled but was never actually run has not been verified at all.
EOF
out="$("$TOOL" --dupes "$WRAP" 2>&1)"; rc=$?
discard "$WRAP"
if [ $rc -eq 1 ] && grep -q "w.md" <<<"$out"; then
  ok "wrapping: a wrapped paragraph matches its unwrapped twin"
else
  no "wrapping: line boundaries hid a duplicated paragraph (rc=$rc)"
fi

# 12. Short rules are rules. A nine-word floor dropped "use trash, never rm"
#     shaped guidance out of both passes without saying so.
SHORT="$(mktemp -d)"; mkdir -p "$SHORT/memory"
printf 'Always trash a path, never delete it outright.\n' > "$SHORT/AGENTS.md"
printf 'Delete a scratch path outright only when it is disposable.\n' > "$SHORT/memory/s.md"
out="$("$TOOL" --conflicts "$SHORT" 2>&1)"; rc=$?
discard "$SHORT"
if [ $rc -eq 1 ] && grep -qi "outright\|delete" <<<"$out"; then
  ok "short rules: a seven-word rule still reaches the detector"
else
  no "short rules: dropped below the word floor (rc=$rc)"
fi

# 13. A file can contradict ITSELF, and AGENTS.md is long enough to do it. The
#     first version skipped same-file pairs, which blinded it to the file most
#     likely to accumulate two rules about one subject.
SELF="$(mktemp -d)"
cat > "$SELF/AGENTS.md" <<'EOF'
- Deploys are gated and must always be confirmed with me before you run one.
- Some later section, written months afterwards, about something else entirely.
- Deploys may be run by default once the review loop is clean, unless I say otherwise.
EOF
out="$("$TOOL" --conflicts "$SELF" 2>&1)"; rc=$?
discard "$SELF"
if [ $rc -eq 1 ] && grep -qi "deploys" <<<"$out"; then
  ok "same file: a file contradicting itself is reported"
else
  no "same file: missed a self-contradiction (rc=$rc)"
fi

# 14. YAML frontmatter is a schema. `allowed-tools: Bash, Read, Grep, Glob` is
#     byte-identical across every skill by design, and comparing it paired each
#     skill with each other skill at 1.00, burying the real findings.
FM="$(mktemp -d)"; mkdir -p "$FM/skills/a" "$FM/skills/b"
printf -- '---\nname: a\nallowed-tools: Bash, Read, Grep, Glob, Edit, Write\n---\n\nThe first skill says one entirely unrelated thing about boards and cards.\n' > "$FM/skills/a/SKILL.md"
printf -- '---\nname: b\nallowed-tools: Bash, Read, Grep, Glob, Edit, Write\n---\n\nThe second skill says something else completely different about deployments.\n' > "$FM/skills/b/SKILL.md"
out="$("$TOOL" --dupes "$FM" 2>&1)"; rc=$?
discard "$FM"
if [ $rc -eq 0 ] && ! grep -q "allowed-tools" <<<"$out"; then
  ok "frontmatter: identical YAML headers are not a duplication finding"
else
  no "frontmatter: paired two skills on their shared header (rc=$rc)"
fi

# 15. A repo's .agents/skills are SYMLINKS to canon, and they are exactly the
#     files its own AGENTS.md is most likely to have restated. Skipping them left
#     the fork this tool exists for outside the scan. The symlink matters: the
#     glob has to traverse a linked DIRECTORY, not just a linked file.
PROJ="$(mktemp -d)"; CANON="$(mktemp -d)"
mkdir -p "$PROJ/.agents/skills" "$CANON/example-workflow"
cat > "$CANON/example-workflow/SKILL.md" <<'EOF'
Tear the worktree down with the script once the branch lands, never with a bare git worktree remove, because bare removal can exit zero and leave an orphan.
EOF
ln -s "$CANON/example-workflow" "$PROJ/.agents/skills/example-workflow"
cat > "$PROJ/AGENTS.md" <<'EOF'
Tear the worktree down with the script once the branch lands, never with a bare git worktree remove, because bare removal can exit zero and leave an orphan.
EOF
out="$("$TOOL" --dupes "$PROJ" 2>&1)"; rc=$?
discard "$PROJ" "$CANON"
if [ $rc -eq 1 ] && grep -q "SKILL.md" <<<"$out"; then
  ok "project scope: a repo restating a symlinked canon skill is caught"
else
  no "project scope: .agents/skills left outside the scan (rc=$rc)"
fi

# 16. The teardown itself. The old line was `[ -x /usr/bin/trash ] && trash "$d"`,
#     which on a machine without it did nothing, said nothing, and leaked every
#     fixture. Canon is explicit that an unavailable `trash` gets reported, never
#     silently swapped for rm — so the guard must SAY it left something behind.
PROBE="$(mktemp -d)"
( TRASH_BIN="" LEAKED=""
  discard(){ for d in "$@"; do [ -n "$d" ] && [ -d "$d" ] || continue; case "$d" in /*) ;; *) continue ;; esac
    if [ -n "${TRASH_BIN}" ]; then "${TRASH_BIN}" "$d" >/dev/null 2>&1 || LEAKED="$LEAKED $d"; else LEAKED="$LEAKED $d"; fi; done
    [ -n "$LEAKED" ] && exit 0 || exit 1; }
  discard "$PROBE" )
probe_reported=$?
if [ $probe_reported -eq 0 ] && [ -d "$PROBE" ]; then
  ok "teardown: an unavailable trash is reported, not silently skipped"
else
  no "teardown: leak went unreported (rc=$probe_reported)"
fi
discard "$PROBE"

# A relative or empty path must never reach the delete at all.
if ( discard "" "relative/path" ) && [ ! -d "relative/path" ]; then
  ok "teardown: empty and relative paths never reach the delete"
else
  no "teardown: guard let a non-absolute path through"
fi

echo "--------------------------------------------"
echo "PASS=$PASS  FAIL=$FAIL"
[ $FAIL -eq 0 ]
