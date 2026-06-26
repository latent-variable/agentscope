---
name: pull-requests
description: How to write pull requests and commits — terse style, structure, and attribution. Load when opening a PR, writing a commit, or summarizing a branch.
allowed-tools: Bash, Read, Grep, Glob
---

# Pull Requests & Commits

House style for PR descriptions and commit messages. Artifacts, so write them *normally* (terse, not ELI5 — ELI5 is only for talking to the user).

## Commit messages

- Subject ≤ ~50 chars, imperative mood. Conventional Commits prefix when the repo already uses it (`feat:`, `fix:`, `chore:`…).
- Body only when the "why" isn't obvious from the diff. Explain intent/tradeoff, not the line-by-line.
- Attribution line for non-trivial commits:
  ```
  Assisted-by: <Agent> <model-id>
  ```
  e.g. `Assisted-by: Claude claude-opus-4-8`. Omit for trivial commits (typo, version bump, whitespace).

## PR descriptions

- **Action before context.** Lead with what changed. Why-it-matters second.
- Terse and punchy. Say it once. Cut hedging preamble.
- Structure: 1–2 sentence summary → bullets of concrete changes → testing/verification → caveats/follow-ups if any.
- No duplicate summaries. One source of truth per fact.
- Don't restate the diff line-by-line; surface what a reviewer can't see (intent, risk, what was verified).
- End the body with the attribution line (same as commits) for non-trivial PRs.

## Review behavior

- Project may ship its own review tooling/skill — check the repo's `AGENTS.md` first.
- When reviewing, one line per finding: location, problem, fix. Cut noise, keep the actionable signal.

## Before pushing

- Confirm tests pass; if they don't, say so plainly with the output. Never report green when it's red.
- Branch off the default branch first if currently on it. Push/open PR only when the user asks (or per the `review-cycle` skill if adopted).
