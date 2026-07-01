---
name: remember
description: >
  Save a durable fact about the user or their work into the shared cross-agent memory (~/.agents/memory),
  then commit + push so every agent (Claude, Codex, Gemini, Pi) sees it. The write-back path: use it
  whenever you learn something worth persisting beyond this session, or when the user says "remember this".
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Remember (cross-agent write-back)

Memory at `~/.agents/memory/` is shared by every agent. Any agent — not just Claude — can contribute. This skill is how Codex, Gemini, and Pi (which have no auto-memory) write durable facts the same way Claude's auto-memory does. One fact per file. Match the existing files' format exactly.

## When to use

- The user says "remember this" / "save this" / "note for next time".
- You learned a durable fact: a preference, a correction/feedback, an ongoing project constraint, or a pointer to an external resource.
- **Not** for: what the repo, git history, or a project's own `AGENTS.md` already records; transient task state; anything only relevant to this one conversation.

## Memory types

- `user` — who the user is (role, skills, preferences).
- `feedback` — guidance on how to work (corrections + confirmed approaches). Include the **why**.
- `project` — ongoing work, goals, constraints not derivable from code/git. Convert relative dates to absolute.
- `reference` — pointers to external resources (URLs, dashboards, tickets).

## Procedure

1. **Dedupe first.** `grep -ril "<topic>" ~/.agents/memory/` — if a file already covers it, **update that file**, don't make a duplicate. Delete memories that turn out wrong (`trash`, never `rm -rf`).

2. **Write the file** `~/.agents/memory/<slug>.md` (kebab-case slug), with this frontmatter:
   ```markdown
   ---
   name: <Short Title>
   description: <one line — used to decide relevance during recall>
   metadata:
     type: user | feedback | project | reference
   ---

   <the fact. For feedback/project, add **Why:** and **How to apply:** lines.>
   ```
   - Absolute dates (today's real date, not "last week").
   - Link related memories with `[[their-slug]]`. Link liberally; a `[[slug]]` with no file yet is fine.

3. **Index it.** Add ONE line to `~/.agents/memory/MEMORY.md`:
   `- [<Title>](<slug>.md) — <hook>`
   (MEMORY.md is the index loaded every session. One line each, no content.)

4. **Ship it** so all agents inherit it:
   ```bash
   cd ~/.agents && git add -A && git commit -m "memory: <slug>" && git push
   ```
   (If `git push` fails on network/sandbox, the commit alone is enough — a backup job or the next push ships it.)

5. **Confirm** in one line: what you saved and where.

## Quality bar (parity across agents)

Every agent writes to the same standard so the weakest model doesn't degrade the shared brain:
- One fact per file. Minimal. No restating the obvious.
- Description line must be genuinely useful for recall; it's what future agents scan.
- If unsure whether something is durable or just this-session, ask rather than guessing.
- Write-back is discretionary and unequal by design: the auto-memory agent (Claude) captures most; read-mostly agents write only clearly-durable facts. Fewer, better memories beat volume.
