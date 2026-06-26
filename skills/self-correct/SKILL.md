---
name: self-correct
description: >
  Audit and repair the shared agent knowledge base (~/.agents) when it drifts from reality —
  removed/renamed dirs or repos, changed paths/flags/commands, superseded facts. Keeps instructions,
  memory, and skills true for every agent on the machine. Use on demand, on a schedule, or whenever
  you notice canon is stale mid-task.
allowed-tools: Bash, Read, Edit, Grep, Glob
---

# Self-correct the knowledge base

Canon at `~/.agents/` is read by every agent (Claude, Codex, Gemini, Pi). One stale fact misleads all of them. Fix the source, don't patch around it.

## When to run

- **Reactively (default):** the moment you discover, during any task, that a canon fact is wrong — a path moved, a repo was deleted, a tool was renamed, a flag changed. Fix it then.
- **Proactively:** on demand or scheduled.

## Procedure

1. **Detect drift.** Run the auditor:
   ```bash
   ~/.agents/bin/verify.sh
   ```
   It checks: symlink integrity (for installed tools), every filesystem path referenced in canon (`AGENTS.md`, `memory/*.md`, `skills/**/SKILL.md`), any GitHub repo referenced under your handle, and git sync state. It prints `DRIFT:` lines for anything broken.

2. **Verify before editing.** Confirm each DRIFT is real (the dir/repo truly moved or is gone), not a transient (unmounted volume, network blip, a `<placeholder>` or `{{template}}`). Never "correct" something you haven't confirmed changed.

3. **Repair the source.** Edit the stale file to match reality:
   - Renamed dir/repo → update the name everywhere it appears (grep first: `grep -rn 'OLD_NAME' ~/.agents`).
   - Removed thing → delete the line/file; drop its pointer in `memory/MEMORY.md`.
   - Changed flag/command/path → update the exact string.
   - Superseded fact → replace; keep one source of truth, no stale duplicate.

4. **Re-verify.** `~/.agents/bin/verify.sh` again — DRIFT for the fixed item should be gone.

5. **Commit + push** (propagates to all agents, backs up):
   ```bash
   cd ~/.agents && git add -A && git commit -m "fix: <what drifted>" && git push
   ```

6. **Report** one line: what you corrected and why.

## Guardrails

- Minimal edits. Correct the fact; don't rewrite the file.
- Recoverable deletes only (`trash`, never `rm -rf`) per global rules.
- Don't auto-correct subjective preferences or anything ambiguous — surface those to the user instead.
- If a referenced GitHub repo 404s, confirm it isn't just private/renamed (`gh repo view`) before deleting the reference.
