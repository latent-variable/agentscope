---
name: review-cycle
description: >
  A standing workflow for EVERY project: branch off main, validate + test, open a PR, run it through
  automated review, merge once it passes clean. This is the user-scope source of truth, projects keep
  only their own commands (test/build/deploy), not this contract. Load whenever you're about to commit,
  open/respond to a PR, or merge in any repo. (Optional: enabled during onboarding.)
allowed-tools: Bash, Read, Grep, Glob
---

# Review cycle (all projects)

Every repo follows this. Don't copy-paste it into each project's `AGENTS.md` (it drifts), this is the single source of truth. A project's own `AGENTS.md` supplies the **project-specific commands** (exact test/build/deploy/emulator invocations, repo name); it defers to this for the workflow.

## 0. Gating tiers, how much autonomy you have

The point is to ship with high confidence **without waiting on the user**. Match the gate to the risk:

- **Docs / config-only** (`AGENTS.md`, `README`, comments, non-functional config): **commit straight to `main`. No branch, no PR.** These encode the user's own instructions; gating them wastes time.
  **Land it in the same turn: commit AND push to `main`.** A doc fix parked on a branch, or waiting on an OK you already have standing for, is a fix that does not exist. Same for canon-consistency work (deleting a stale line from a repo, syncing a managed block): it goes straight to `main` in every repo it touches. If you happened to start on a branch, push it to `main` anyway rather than opening a PR for docs.
- **Code changes:** run the full cycle below, then **merge to `main` autonomously when all three hold:**
  1. **Genuinely self-validated end-to-end.** You actually exercised the path that changed, not just "it compiles." If you *cannot* truly end-to-end validate it, **don't self-merge, escalate to the user.** This is the load-bearing condition.
  2. **Tests green**, and you added/updated tests per the Testing bar (§2) for what you changed.
  3. **Automated review looped to zero high/critical** findings (§5). Mediums are judgment.
  When in doubt about whether validation was real, gate it on the user rather than merging.
- **Deploys** stay gated regardless, unless a specific project says otherwise.

> Autonomy level is a preference. If you'd rather approve every merge yourself, treat §0 as "open the PR and stop", the rest of the cycle still applies.

## 1. Branch, never commit code straight to `main`

- `git checkout -b <type>/<short-desc>` off a clean `main`. Types: `feat/`, `fix/`, `refactor/`, `chore/`, `docs/`.
- **Commit as you go** (canon doctrine): commit each completed+tested chunk, don't leave finished work uncommitted.
- **Worktree only when needed** (default: branch in place). Use one only if right now `git status` shows edits you didn't make, another agent has uncommitted work here, or you're starting a second feature while one's open for review.

## 2. Validate before opening the PR, the Testing bar

Autonomous merge rests entirely on validation being *real*:

- **Prefer integration and end-to-end tests.** They exercise actual features and catch regressions. Self-validation means you ran the thing end-to-end, not that it compiled.
- **Don't bloat.** No unit-testing everything, no mocked-API tests that drift from reality. A unit test only when the logic is genuinely pure and worth pinning.
- **A good test finds gaps, verifies the feature works, or proves you didn't break what worked.** Ship those tests in the same PR.
- **State plainly what you could NOT verify** (GUI, audio, paid paths, anything needing a device/permission). Never claim an end-to-end path works when only part was checked.
- Conventional-commit titles; terse PR body with **Summary** + **Test plan**. `Assisted-by: <Agent> <model-id>` on non-trivial commits.

### What makes a test worth writing (this is the whole bar)

"Don't bloat" is NOT permission to skip. Read together, the two rules above have
one axis, and it is not the test's tier: **does a wrong answer here announce
itself, or does it look fine?**

- **Code that FAILS LOUDLY when wrong needs little testing.** It throws, the
  build breaks, the request 500s. The failure is its own alarm.
- **Code that RETURNS A PLAUSIBLE WRONG ANSWER needs a test, always, whatever
  tier that takes.** Nothing crashes, everything is green, and the product
  quietly tells a user something false. This is where the real defects live,
  and it is exactly the code that "no unit-testing everything" gets misread as
  excusing.

Ask it directly: **if this were wrong, what would I see?** "A number that looks
like a number", "a pin on a map", "a name in a list", "a score" → write the
test. Bloat is asserting *mechanism* (which selector, which branch, how the
regex is spelled). Value is asserting *the claim the code makes to a user*.

**An untested file you are touching is a finding, not a convenience.** Zero
coverage is why a silent bug got in and why nothing caught it. Before editing
one, write tests for the behaviour that is already there, then change it. That
pass alone routinely surfaces a second live bug.

**Prove the test is not vacuous.** A validation that would pass *even with your
fix removed* proves nothing. When a check depends on the input happening to hit
the interesting case (a stochastic dataset, a race, a rare branch), add a
**control** in the same run: exercise the same code path with the guard
disabled or a known-bad input, and assert it *fails* there. If you can't build
a control, say so rather than reporting a green you don't trust.

**Several failure modes can share one outcome**, so a test asserting the
outcome proves nothing about which one fired. If an unreachable meter and an
exhausted budget both produce "defer", assert the specific *reason*, not the
verdict. Otherwise a broken stub passes for the wrong reason.

**Use real values when the numbers carry meaning.** Real coordinates, real
measured thresholds, a real payload. Then a failure tells you *what broke in the
world*, and the constants can't drift into nonsense without a test noticing.

**Stubbing the network to test YOUR logic is fine; asserting a vendor's
behaviour is not.** "Don't mock external APIs" bans tests that encode what a
third party returns (they drift and then lie). It does not ban stubbing
transport to check what *you* send and how *you* interpret what comes back.
Pair any such test with one real call in a script or smoke tier.

*Case study.* A module with zero tests pinned a real business 3710km away as a
"local competitor", on a customer-facing map, for weeks. Nothing threw; the pin
just looked like a pin. Writing the missing tests took an hour and immediately
surfaced a **second** live bug: every business with an apostrophe in its name
was reported "not found" over punctuation alone.

## 3. Open the PR

```bash
git push -u origin <branch>
gh pr create --base main --title "feat: …" --body "## Summary
…
## Test plan
- [ ] …"
```

## 4. Automated review, required before merge

Trigger whatever automated reviewer you use (a hosted PR reviewer, a CI review bot, or a local agent review). Configure the trigger in the project's `AGENTS.md` so it's one command. The point is a second set of eyes that didn't write the code, every PR, before merge.

## 5. The severity-gated loop

- **Critical / high = blocking.** While any round returns even one high, address **every** item raised that round (high *and* medium), push, re-request review. Repeat until a full round comes back with **zero highs**.
- **Medium / low = judgment.** Once no highs remain: fix the worthwhile ones, note why not on the rest, proceed.
- After each push, re-request review and **confirm the new review ran against `HEAD`** before trusting its verdict, reviewers sometimes report against an earlier commit.
- **Reply on the PR each round** listing what was addressed.
- **Pull feedback from all THREE places, not one.** Many reviewers (GitHub's own review UI, most review bots) post their top-level verdict as a PR **review** and their findings as **inline review comments** — and *neither shows up in `--json comments`*, so a watcher that reads only issue comments will miss the actual review and wrongly conclude nothing came back. Pull all three:
  - top-level verdict + state: `gh pr view <n> --json reviews`
  - inline line-level findings: `gh api repos/<owner>/<repo>/pulls/<n>/comments`
  - issue-level comments (trigger acks, bot chatter): `gh pr view <n> --json comments`

  If you poll manually, poll `reviews`, not `comments`.
- **Style vs correctness is the call you are paid to make.** A finding about a real failure mechanism (wrong result, crash, data loss, security, broken flow) gets fixed even when it is inconvenient. A finding about naming, structure preference, extraction, defensive hardening with no failure mechanism, or test shape is a suggestion — take it if it is cheap and improves the code, decline it with a reason if it is churn. **Don't fix a style finding just to clear the ledger.**
- **When you disagree, decline with evidence, don't silently comply.** Say so on the PR with the lines or tests that prove it. A wrong finding you quietly "fix" makes the code worse and teaches the reviewer nothing.
- If highs persist after ~6 rounds, stop and ask the user how to proceed.

## 5b. HOW to wait for the review

Agents keep rediscovering this the hard way. The failure is always the same shape: the PR is pushed, the review lands, and the agent is **sitting there having done nothing about it**, either because it armed no watcher at all, or because it armed one that went silent. Don't invent a new approach per session.

**The rule: never poll by hand, never "wait", never end a turn saying you'll check back.** After you push, arm exactly ONE watcher, keep working on something else, and act when it fires.

Pick the primitive your harness gives you:

- **One notification, "the review landed"** — the normal case, once per round: a **backgrounded** shell loop that **exits** when the review appears. Exiting is what fires the notification.
- **Many notifications over a session** (several PRs, or a long fix loop): a **persistent** monitor primitive, where each output line becomes its own notification.
- **Never `&` or `nohup`.** A shell-detached process is invisible to the harness: it exits into a temp file and you are never told. This is the single most common reason an agent "waited" forever.

Tools with no background primitive: run the same script in the **foreground** with a bounded wait, then act on what it prints. Still never end a turn intending to check later.

```bash
cd <repo-path>
PR=207; REPO=owner/name
before=$(gh pr view "$PR" --json reviews --jq '.reviews | length')   # BEFORE you push
git push
for i in $(seq 1 40); do                                             # 40 x 30s = 20 min
  sleep 30
  now=$(gh pr view "$PR" --json reviews --jq '.reviews | length' 2>/dev/null) || now=$before
  [ -z "$now" ] && now=$before                                       # a gh blip must not kill the watch
  if [ "$now" -gt "$before" ]; then
    echo "REVIEW LANDED on $REPO#$PR"
    gh pr view "$PR" --json reviews --jq '.reviews[-1] | "\(.state)\n\(.body)"'
    gh api "repos/$REPO/pulls/$PR/comments" --jq '.[] | "\(.path):\(.line) \(.body)"'
    exit 0
  fi
done
echo "TIMED OUT after 20m, no new review on $REPO#$PR"
exit 1
```

### The six properties any version of this must have

1. **Baseline BEFORE the trigger.** Capture `before` ahead of the `git push`. Baseline after, and a fast review slips into the gap, the count already matches, and you wait forever.
2. **Poll `reviews`, not `comments`.** Per §5 the verdict is a PR *review* and the findings are *inline review comments*; neither appears in `--json comments`.

   **The nastiest variant: a watcher that counts FINDINGS.** Polling inline review comments looks like it works, because it fires correctly on every round that finds something. It goes permanently silent on the one round you are waiting for — **a clean review posts a verdict body and ZERO inline comments**, so "no new findings" and "reviewed, nothing open" are the same observation to it. Count **reviews**; read the verdict out of the newest review **body**.
3. **Survive a transient `gh` failure.** One failed call must not end the watch or be read as a change. Fall back to the previous value.
4. **Print the verdict AND the findings when it fires.** A bare "a review appeared" costs a whole extra round trip before you can act.
5. **Bounded, and it MUST SPEAK on timeout.** A loop that runs out and exits silently is the worst outcome: silence is indistinguishable from still-waiting.
6. **Exit when it fires** (that is the notification), then **re-arm after the next push.** One watcher per round. An unbounded `tail -f` / `while true` stays armed after the event and gives you nothing.

**Trap: GitHub's review `state` is NOT the verdict.** A reviewer can post as `COMMENTED` while requesting changes in the body, so an agent gating on `state == "CHANGES_REQUESTED"` reads a blocking review as a pass. Count reviews to detect arrival; read the verdict out of the body.

## 6. Merge (per the §0 gate)

- **Code:** once highs are cleared and the §0 conditions hold, **merge it.** Never merge over an outstanding high. If the core change couldn't be genuinely end-to-end validated, gate it on the user.
- After merge: `gh pr merge --delete-branch`, then prune locally (`git fetch -p`, remove worktree, delete local branch). Clean up before the next task.

## 7. When the reviewer is wrong, fix the styleguide

Models lag the codebase and sometimes flag intentional/correct code. When a reviewer repeatedly flags something correct, **encode a "don't flag" rule where your reviewer reads it** (e.g. a styleguide file), don't just argue in comments. Rule of thumb: writing the same defense twice → write it into the styleguide instead.

---

**Changing the workflow:** edit THIS file, then every project inherits it. Don't re-litigate it per repo.
