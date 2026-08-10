---
name: cleanup
description: >
  Full consistency sweep of the agent knowledge base: user scope (~/.agents) plus every repo's
  project scope. Finds contradictions between memories, decisions that landed in one layer and
  not the others, stale facts, canon restated inside repos, and project-scope overrides that no
  longer make sense. Fixes what it finds in the same turn. Load when the user asks for a cleanup, a
  canon review, or "check our scope", and after any session that changed a rule in several places.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

# Cleanup: review the knowledge base

## You are the reviewer. That is the whole point.

Canon is reviewed by **you**, on the user's instruction, doing this sweep. An
automated reviewer is a tool you may point at a diff; it is not the authority and
it is not always right. In the session that produced this skill one found a real
data-loss bug, and it also blocked five times on work already fixed, and once
recommended a change that would have disabled the tool it was reviewing.

So: read its findings, verify each one, fix what is real, decline what is not with
evidence. **You own the outcome.** If it holds a block on something you declined
with proof, that is a defect in the orchestrator worth telling the user about, not a
reason to change correct code.

`self-correct` is the reactive version of this (fix drift you tripped over
mid-task). This skill is the deliberate sweep.

## Order of passes

Cheapest and most mechanical first, so the expensive judgment work runs on a
clean board.

### 1. Mechanical: drift detector and tests

```bash
~/.agents/bin/verify.sh          # symlinks, skill parity, referenced paths, repos, git
bash ~/.agents/tests/run-tests.sh
```

**Any red must be fixed or explained to the user in the same turn, never silenced.**
A test asserting a state canon abolished is stale and should change. A test
reporting a real weakness stays red and gets surfaced. Red you cannot account
for is the one thing you may not leave behind.

Watch for a checker that is *permanently* red. `verify.sh` once ended in
`DRIFT FOUND` on 15 lines that were all false, which is exactly how real drift
gets ignored. A checker nobody believes is worse than no checker.

### 2. The big one: did the decision reach every layer?

**This is where nearly all drift comes from.** A rule is written down three or
four times in different languages, and changing one and stopping is the default
failure. Layers to check for any rule you touch:

| Layer | Where |
|---|---|
| Prose | `AGENTS.md` |
| Fact | `memory/*.md` + its pointer in `MEMORY.md` |
| Procedure | `skills/*/SKILL.md` |
| Assertion | `bin/verify.sh` |
| Test | `tests/*.sh` |
| Exemption | `.verify-ignore-paths` |
| Installer | `bin/sync.sh`, `bin/project-sync.sh` |

```bash
grep -rn '<the old fact>' ~/.agents        # before editing anything
```

Ask directly: **does a script or a test assert the old state?** Those fail loudly
and forever.

*Case study.* agy was unwired from user scope on 2026-07-28 and the decision
landed in `sync.sh` alone. `verify.sh` kept asserting the deleted symlinks,
`run-tests.sh` kept probing agy, and `project_agents_user_scope.md` still told
every agent agy was wired. One decision, four places, one updated, six days of
false alarms.

### 3. Memory integrity

```bash
cd ~/.agents/memory
ls *.md | grep -v MEMORY.md | sort > /tmp/f.txt
grep -o '](\([a-zA-Z0-9._-]*\.md\))' MEMORY.md | sed 's/](//;s/)//' | sort > /tmp/i.txt
comm -23 /tmp/f.txt /tmp/i.txt    # files with no pointer
comm -13 /tmp/f.txt /tmp/i.txt    # pointers with no file
```

Both directions matter. An unindexed memory is invisible; a dangling pointer
sends an agent hunting.

### 4. Contradictions BETWEEN memories

Two memory files can each be internally coherent and disagree with each other.
Nothing mechanical catches this; you have to read for it.

**Ground-truth every factual claim against the system, not against another
document.** A config file, `gh`, the filesystem, a live command.

*Case study.* One memory file named a local model as the active default. Another
memory file in the same directory recorded that same model **rejected** by a
bake-off three days later. Ground truth was the config the tool actually reads,
which named a third. The bake-off file was right; the first was never updated
when the result came in.

Highest-yield pairs to check: model/tool defaults, which reviewer is live,
project directories, anything with a version or a date in it.

### 5. Stale facts vs reality

Anything canon asserts about the world can rot. Verify, don't assume:

```bash
ls <your project dirs, as listed in memory/reference_project_dirs.md>
gh repo list <your-handle> --limit 200 --json name -q '.[].name' | wc -l
```

Dead project dirs, renamed repos, changed counts, an exception listing a repo
that has since been wired. Fix the source; never leave a known-wrong fact "for
later".

### 6. Canon echoed inside repos

```bash
for r in <your project dirs>/*/; do
  [ -e "$r/.git" ] || continue
  ~/.agents/bin/canon-echo.sh "$r" | grep -v "clean" && echo "  ^ $(basename $r)"
done
```

A copy of a canon rule inside a repo is a fork: canon moves, the copy does not,
and an agent reading the repo obeys the stale copy. **Delete the copy** rather
than updating it to match.

### 7. Project-scope overrides that no longer make sense

A repo may legitimately differ from canon, marked:

```
<!-- canon-override: <rule> — <why this repo differs> (YYYY-MM-DD) -->
```

Find every one and **judge it, don't just count it**:

```bash
grep -rn "canon-override:" ~/Documents/*/*/[AC]*.md ~/Documents/*/[AC]*.md 2>/dev/null \
  | grep -v "a real exception is marked"     # the boilerplate footer, not an override
```

For each, four questions:

1. **Is the reason still true?** An override citing a removed reviewer, a retired
   product, or a decision the user has since reversed is dead. Delete it.
2. **Is it one line of what DIFFERS,** or has it grown into a restatement of the
   whole rule? A restatement is the fork this system exists to prevent, marker or
   not.
3. **Does it actually contradict canon,** or is it just repeating canon with a
   marker stapled on to silence the checker? The second is worse than an
   unmarked echo, because it looks sanctioned.
4. **Would a fresh agent reading only that repo do the wrong thing?** That is the
   real test. If the override makes the repo's behaviour *more* correct there,
   keep it. If it only makes the repo *different*, kill it.

An override is a standing exception to the user's own instructions, so the bar is
high and it needs a date. Undated means unreviewed. Ask the user before keeping one
you cannot justify from the repo's own facts.

### 8. Secrets, briefly

Canon lives in a **private** repo and that is the point: design decisions,
specs, patterns and preferences belong there. Real credentials do not.

```bash
cd ~/.agents
git ls-files | grep -iE "secret|\.key$|\.pem$|auth|token|\.env"
git log --all -p | grep -nIE "(sk-[A-Za-z0-9]{20,}|rk_live_|ghp_|BEGIN [A-Z ]*PRIVATE KEY)"
```

**Prove the scan works before trusting a clean result** (pipe a fake key through
the same pattern). Verified clean 2026-08-05: `secrets/` is gitignored and
untracked, and the only history hit is a redacted `rk_live_...` placeholder in
prose.

## Verification discipline

The failure that recurs is **a check that cannot fail**. Three instances shipped
in one PR during this skill's session, all on code paths that delete files: a
test asserting "directory gone" but never "still recoverable"; a guard branch
made unreachable by `set -e`; a validation loop over an empty list returning
success by vacuous truth.

So, for anything you fix here:

- **Run the control.** Revert your fix, confirm the test fails, restore it. A
  test that passes against the broken code proves nothing.
- **Test the job, not only the guard.** Guard tests pass a change that guards
  harder while breaking the feature. One test asserting the tool's actual
  purpose is what caught an inode "hardening" that disabled the very case the
  tool existed for.
- **Absence of counter-evidence is not evidence.** An empty result from a checker
  that did not run is not a clean bill.

## Landing it

Cleanup is docs and canon work: **commit and push to `main` in the same turn.**
No branch, no PR. A canon fix parked on a branch does not exist.

```bash
cd ~/.agents && git add -A && git commit -m "fix: <what drifted>" && git push
```

If a fix touches `bin/` or `tests/` (real code), that is the review cycle's
territory: branch, validate, PR, automated review, merge. Note that
`autopush.sh` will **not** commit those for you, by design.

## Report

Lead with what was actually wrong, ranked. For each: what it was, what it is
now, and how you verified. Then, separately, what you checked and found clean,
in one line each; a clean bill is information too.

Surface to the user rather than deciding yourself: an override you cannot justify, a
contradiction where you cannot establish which side is true, and any red check
you could not fix.

## Do not

- Do not "fix" a fact you have not verified changed.
- Do not silence a checker to get a green board.
- Do not update a canon copy inside a repo to match; delete it.
- Do not rewrite whole files. Correct the fact, keep the entry minimal.
- Do not treat the automated reviewer's verdict as final. Verify, then decide.
