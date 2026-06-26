# agentscope — one user-scope brain for every agent

Clone it to `~/.agents`, tell your agent to onboard you, and **Claude Code, Codex, Antigravity (Gemini), Pi**, and any future tool that follows the `AGENTS.md` / Agent Skills conventions all read the same instructions, skills, and memory.

Stop re-teaching every tool who you are and how you work. Teach it once, here.

## Install

```bash
git clone https://github.com/<you>/agentscope.git ~/.agents
```

Then open any agent CLI and say:

> **"Onboard me with agentscope."**

The agent runs the **`onboarding`** skill: it interviews you (who you are, where your projects live, how you like to communicate), fills in the template, detects which agent CLIs you have installed, and wires them all to `~/.agents`. Two minutes, then every tool knows you.

Prefer to do it by hand? `~/.agents/bin/sync.sh` wires the symlinks; edit `AGENTS.md` + `memory/user_profile.md` yourself.

## What's inside

```
~/.agents/
  AGENTS.md     # canonical global instructions (identity is a fill-in template)
  skills/       # portable SKILL.md skills, loaded on demand by name
  memory/       # durable cross-agent facts; read MEMORY.md first
  bin/sync.sh   # idempotent installer — points each tool's native paths here
  bin/verify.sh # drift detector — flags stale paths/links so an agent self-corrects
```

**Skills shipped:** `onboarding` (the setup interview), `remember` (cross-agent memory write-back), `self-correct` (keep canon true), `project-scope` (per-repo agent context), `review-cycle` (branch → PR → review → merge), `pull-requests`, `draft-response`, `security-audit`.

## How each tool gets wired

| Tool | Instructions → `AGENTS.md` | Skills | Memory |
|------|----------------------------|--------|--------|
| Claude Code | `~/.claude/CLAUDE.md` (symlink) | `~/.claude/skills/*` | `~/.claude/projects/<home>/memory` → `~/.agents/memory` |
| Codex | `~/.codex/AGENTS.md` (symlink) | `~/.codex/skills/*` | via AGENTS.md pointer |
| Antigravity (Gemini) | `~/.gemini/GEMINI.md` + `AGENTS.md` | `~/.gemini/skills/*` | via AGENTS.md pointer |
| Pi | `~/.pi/agent/AGENTS.md` (symlink) | reads `~/.agents/skills/` natively | via AGENTS.md pointer |

`sync.sh` only wires the tools it finds installed; the rest are skipped. Re-run it anytime (idempotent) after adding a tool or a skill.

## Keeping it current

- **Self-correction (default):** any agent that spots a stale fact mid-task fixes the source here, commits, and pushes — so every other agent inherits the fix. Rule in `AGENTS.md`; procedure in the `self-correct` skill. Drift detector: `bin/verify.sh`.
- **Back it up:** make it your own private repo and push. `cd ~/.agents && git add -A && git commit && git push`.

## Optional: spoken summaries

If you live in your terminal and like hearing what your agent did, enable the **🔊 Speak to me** convention during onboarding and pair it with **[Yap](https://github.com/latent-variable/Yap)** — local-first, on-device TTS + speech-to-text for macOS. macOS only for now.

## The one honest seam

Read-sharing is instant (symlinks). **Write-back** differs: Claude Code's auto-memory writes straight into `~/.agents/memory/`. Other tools mostly read; when they record something durable they use the `remember` skill to drop it in by hand. True multi-agent memory write-back isn't a solved standard yet — this is the pragmatic version.
