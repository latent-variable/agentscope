---
name: project-scope
description: >
  How agent context works at PROJECT scope (inside a repo) vs USER scope (~/.agents). Where project
  memory + shared skills live, how the symlink bridge works, and the scope-confusion trap to avoid.
  Load when working in any repo that has a `.agents/` dir, or when bootstrapping a new repo.
allowed-tools: Bash, Read, Grep, Glob
---

# Project scope vs user scope

Two layers. Don't conflate them, conflating them is exactly the bug this skill exists to prevent.

- **USER scope = `~/.agents`**: global, transcends every project. The canonical brain (`AGENTS.md`, `memory/`, `skills/`) symlinked into each agent CLI. Facts about the user, cross-project doctrine, reusable skills.
- **PROJECT scope = `<repo>/.agents/`**: this repo only. Per-project memory + a symlinked copy of the canon skills. Gitignored.

## Layout (per repo, after bootstrap)

```
<repo>/
  .agents/
    memory/     all agents read+write here; ~/.claude/projects/<enc>/memory is symlinked to it
    skills/     symlinks -> ~/.agents/skills/*
    README.md
  .gitignore    (.agents/ and .claude/ ignored)
  AGENTS.md     committed; carries an "Agent context" pointer block
```

The bridge: Claude stores per-repo memory at `~/.claude/projects/<encoded-cwd>/memory`. Bootstrap symlinks that → `<repo>/.agents/memory`, so Claude's auto-memory and codex/gemini/pi all read+write **one** dir. Encoded path = abs repo path with `/`→`-`.

## What belongs in a repo's AGENTS.md (the no-regurgitation rule)

**A project file states only what is true of THIS repo.** Anything that holds across projects
already lives in user-scope canon and must NOT be restated here, not even "for convenience".

| Belongs in project scope | Never in project scope (it's canon) |
|---|---|
| Commands: build, test, emulator, deploy | The review/merge workflow itself |
| This repo's architecture, invariants, traps | Commit style, attribution lines |
| Its ticket board NAME, and gates unique to it | Ticket-board posture, how to write cards |
| Product decisions an agent must not "fix" | Writing rules, memory rules, delete-safely rules |
| Named exceptions where this repo genuinely differs | Dependency-audit doctrine, exposure rule |

**A pointer is the maximum.** `Follows the user-scope workflow. Project gates: <list>` is
right. Re-summarising what that skill says (branch, validate, PR, severity loop, tiers) is wrong,
even when the summary is currently accurate.

**Why this is a rule and not a preference: a copy is a fork.** Canon changes; the copies don't.
Every duplicated line becomes a stale line that quietly contradicts canon, and an agent reading
the repo obeys the contradiction. Real case: canon flipped ticket boards to agent-managed, and
three repos still ordered agents to "never mirror work onto the board" three weeks later, because
the posture had been helpfully pasted into each of them. Same story with a commit-attribution line
copied into repo commit conventions after canon changed it.

**So when you find canon restated in a repo file, delete it** (docs go straight to main, no ask).
Do not "update it to match" — that just resets the clock on the same failure.

### When a repo genuinely differs: the override protocol

Sometimes a repo really does need something canon doesn't say, or needs the opposite. That is
legitimate. What makes it survive is the FORM, because an override written as a paragraph is
indistinguishable from a copy, and it rots the same way.

An override is **one line of what differs, with the marker above it**:

```markdown
<!-- canon-override: <which rule> — <why this repo differs> (YYYY-MM-DD) -->
- Human signs every merge here; the deploy target is regulated.
```

Rules for it:

- **Name the canon rule you are overriding.** "merge gate", "deploy gating", "writing rules". If you
  can't name it, you are not overriding anything, you are copying.
- **State only the delta.** Never restate the rule you are departing from. The reader has canon.
- **Date it.** An override is a decision at a point in time, and the date is what lets someone later
  ask whether it still holds.
- **One line, or two.** If it needs a section, it is probably project design (fine, put it in the
  architecture part of the file) or it is canon in disguise (delete it).

### The check that catches this for you

`bin/canon-echo.sh [path ...]` greps a repo's agent file for canon restated in it, and names which
canon file owns each rule. `--list` shows what it looks for. Every pattern in it is a rule that
actually drifted in the wild. The `canon-override:` marker above a line suppresses it, so the tool
and the protocol are the same thing.

Run it when you start work in a repo, when you edit that repo's AGENTS.md, and after any canon
change that touched a rule projects like to repeat. It exits 1 when it finds something, so it drops
straight into a hook or a nightly sweep.

### Starting a new repo

`bin/project-sync.sh <repo>` wires the scope and writes the managed context block. The repo's own
AGENTS.md should then carry ONLY these, in this order:

1. **What this project is**, in two or three sentences.
2. **Commands** an agent needs: build, test, run, deploy.
3. **Architecture and invariants**, including product decisions an agent must not "fix".
4. **Traps** this repo has actually hit, with the evidence.
5. **Overrides**, in the format above, if any. Usually there are none.

If you catch yourself writing the workflow, the commit style, or how to use a tool, stop: that is
canon, and the sentence you are typing is a future contradiction.

## The scope-confusion trap (read this)

`.claude`, `.agents`, `CLAUDE.md`, and memory dirs are frequently **symlinks**. Writing one path can land somewhere else; a path existing doesn't mean your write reached the canon. Before claiming "I updated memory / canon":

```bash
readlink <path>        # where does this actually point?
ls -l <path>           # symlink? real file?
git -C <repo> status   # did my "commit" land in the repo I think?
```

Real incident this prevents: an agent edited a project's `CLAUDE.md` believing it was the global canon, and reported memory writes that never happened. Verify the target, don't assume.

## Where to write a memory

- Fact about **the user or cross-project doctrine** → user scope. Use the `remember` skill (`~/.agents/memory/` + `MEMORY.md` pointer + commit/push).
- Fact about **this project only** (its quirks, decisions, gotchas) → `<repo>/.agents/memory/` + a line in that repo's `.agents/memory/MEMORY.md`. Gitignored, so no commit needed, but it's local-only, not backed up.

## First time in a repo (new or existing), set it up, don't retrofit

Project scope should already exist when you start work. Check; if it's not wired, wire it **before** substantive work, don't leave it for a later manual fix.

```bash
[ -d .agents/skills ] || ~/.agents/bin/project-sync.sh .   # bootstrap if missing
```

- **New repo** (`git init` / fresh clone): bootstrapping is part of setup, same tier as the first commit.
- **Existing repo not yet wired**: bootstrap on first touch, then continue your task.
- Already wired: nothing to do (idempotent; safe to re-run to refresh the block).

## Bootstrap / refresh a repo

```bash
~/.agents/bin/project-sync.sh <repo-dir>     # idempotent; default cwd
~/.agents/bin/project-sync.sh --check <dir>  # audit wiring
```

Only `AGENTS.md` + `.gitignore` are git-tracked changes; everything else is gitignored.
