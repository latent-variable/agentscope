---
name: project-scope
description: >
  How agent context works at PROJECT scope (inside a repo) vs USER scope (~/.agents). Where project
  memory + shared skills live, how the symlink bridge works, and the scope-confusion trap to avoid.
  Load when working in any repo that has a `.agents/` dir, or when bootstrapping a new repo.
allowed-tools: Bash, Read, Grep, Glob
---

# Project scope vs user scope

Two layers. Don't conflate them — conflating them is exactly the bug this skill exists to prevent.

- **USER scope = `~/.agents`** — global, transcends every project. The canonical brain (`AGENTS.md`, `memory/`, `skills/`) symlinked into each agent CLI. Facts about the user, cross-project doctrine, reusable skills.
- **PROJECT scope = `<repo>/.agents/`** — this repo only. Per-project memory + a symlinked copy of the canon skills. Gitignored.

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
- Fact about **this project only** (its quirks, decisions, gotchas) → `<repo>/.agents/memory/` + a line in that repo's `.agents/memory/MEMORY.md`. Gitignored, so no commit needed — but it's local-only, not backed up.

## First time in a repo (new or existing) — set it up, don't retrofit

Project scope should already exist when you start work. Check; if it's not wired, wire it **before** substantive work — don't leave it for a later manual fix.

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
