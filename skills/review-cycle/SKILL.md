---
name: review-cycle
description: >
  A standing workflow for EVERY project: branch off main, validate + test, open a PR, run it through
  automated review, merge once it passes clean. This is the user-scope source of truth — projects keep
  only their own commands (test/build/deploy), not this contract. Load whenever you're about to commit,
  open/respond to a PR, or merge in any repo. (Optional: enabled during onboarding.)
allowed-tools: Bash, Read, Grep, Glob
---

# Review cycle (all projects)

Every repo follows this. Don't copy-paste it into each project's `AGENTS.md` (it drifts) — this is the single source of truth. A project's own `AGENTS.md` supplies the **project-specific commands** (exact test/build/deploy/emulator invocations, repo name); it defers to this for the workflow.

## 0. Gating tiers — how much autonomy you have

The point is to ship with high confidence **without waiting on the user**. Match the gate to the risk:

- **Docs / config-only** (`AGENTS.md`, `README`, comments, non-functional config): **commit straight to `main`. No branch, no PR.** These encode the user's own instructions; gating them wastes time.
- **Code changes:** run the full cycle below, then **merge to `main` autonomously when all three hold:**
  1. **Genuinely self-validated end-to-end.** You actually exercised the path that changed, not just "it compiles." If you *cannot* truly end-to-end validate it, **don't self-merge — escalate to the user.** This is the load-bearing condition.
  2. **Tests green**, and you added/updated tests per the Testing bar (§2) for what you changed.
  3. **Automated review looped to zero high/critical** findings (§5). Mediums are judgment.
  When in doubt about whether validation was real, gate it on the user rather than merging.
- **Deploys** stay gated regardless, unless a specific project says otherwise.

> Autonomy level is a preference. If you'd rather approve every merge yourself, treat §0 as "open the PR and stop" — the rest of the cycle still applies.

## 1. Branch — never commit code straight to `main`

- `git checkout -b <type>/<short-desc>` off a clean `main`. Types: `feat/`, `fix/`, `refactor/`, `chore/`, `docs/`.
- **Commit as you go** (canon doctrine): commit each completed+tested chunk — don't leave finished work uncommitted.
- **Worktree only when needed** (default: branch in place). Use one only if right now `git status` shows edits you didn't make, another agent has uncommitted work here, or you're starting a second feature while one's open for review.

## 2. Validate before opening the PR — the Testing bar

Autonomous merge rests entirely on validation being *real*:

- **Prefer integration and end-to-end tests.** They exercise actual features and catch regressions. Self-validation means you ran the thing end-to-end, not that it compiled.
- **Don't bloat.** No unit-testing everything, no mocked-API tests that drift from reality. A unit test only when the logic is genuinely pure and worth pinning.
- **A good test finds gaps, verifies the feature works, or proves you didn't break what worked.** Ship those tests in the same PR.
- **State plainly what you could NOT verify** (GUI, audio, paid paths, anything needing a device/permission). Never claim an end-to-end path works when only part was checked.
- Conventional-commit titles; terse PR body with **Summary** + **Test plan**. `Assisted-by: <Agent> <model-id>` on non-trivial commits.

## 3. Open the PR

```bash
git push -u origin <branch>
gh pr create --base main --title "feat: …" --body "## Summary
…
## Test plan
- [ ] …"
```

## 4. Automated review — required before merge

Trigger whatever automated reviewer you use (a hosted PR reviewer, a CI review bot, or a local agent review). Configure the trigger in the project's `AGENTS.md` so it's one command. The point is a second set of eyes that didn't write the code, every PR, before merge.

## 5. The severity-gated loop

- **Critical / high = blocking.** While any round returns even one high, address **every** item raised that round (high *and* medium), push, re-request review. Repeat until a full round comes back with **zero highs**.
- **Medium / low = judgment.** Once no highs remain: fix the worthwhile ones, note why not on the rest, proceed.
- After each push, re-request review and **confirm the new review ran against `HEAD`** before trusting its verdict — reviewers sometimes report against an earlier commit.
- **Reply on the PR each round** listing what was addressed. Pull feedback via `gh pr view <n> --comments`.
- If highs persist after ~6 rounds, stop and ask the user how to proceed.

## 6. Merge (per the §0 gate)

- **Code:** once highs are cleared and the §0 conditions hold, **merge it.** Never merge over an outstanding high. If the core change couldn't be genuinely end-to-end validated, gate it on the user.
- After merge: `gh pr merge --delete-branch`, then prune locally (`git fetch -p`, remove worktree, delete local branch). Clean up before the next task.

## 7. When the reviewer is wrong, fix the styleguide

Models lag the codebase and sometimes flag intentional/correct code. When a reviewer repeatedly flags something correct, **encode a "don't flag" rule where your reviewer reads it** (e.g. a styleguide file) — don't just argue in comments. Rule of thumb: writing the same defense twice → write it into the styleguide instead.

---

**Changing the workflow:** edit THIS file, then every project inherits it. Don't re-litigate it per repo.
