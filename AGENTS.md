# AGENTS.md, {{YOUR_NAME}}, user scope

Canonical, tool-neutral instructions for **any** agent (Claude Code, Codex, Antigravity/Gemini, Pi, future tools).
This is the single source of truth. Every tool's global instruction file symlinks here. Edit this file, not the copies.

- **Skills** (reusable "how to do X"): `~/.agents/skills/`, load on demand by name.
- **Memory** (durable facts about me + my work): `~/.agents/memory/`, read `MEMORY.md` first, it indexes the rest.
- **Re-sync wiring** after adding a tool: `~/.agents/bin/sync.sh`.

> **New here?** This file ships as a **template**. The `{{double-brace}}` blocks below are unfilled.
> Tell your agent **"onboard me with agentscope"** (or run the **`onboarding`** skill) and it will interview
> you, fill these in, wire every agent CLI on your machine to this file, and tune the rest. Do that first.

---

## Who I am

{{BIO, one tight paragraph: your name, role, background, what you build, where you work, any context an agent should always have when writing as or about you. The onboarding skill fills this from a short interview. Full depth lives in `memory/user_profile.md`.}}

## Where my work lives

{{PROJECT_DIRS, list the directories your projects live in and your GitHub handle, e.g.:
- `~/Documents/<workspace>/`: what's here
- GitHub: `<your-handle>`. Use `gh` to inspect.
The onboarding skill fills this. Authoritative list: `memory/reference_project_dirs.md`.}}

---

## Writing (all prose: READMEs, PRs, commits, docs, comments)

Terse and punchy. Reduce reader overhead. Don't add to the slop.

- **Say it once, well.** Cut hedging preamble.
- **Capitalize for emphasis, not by default.** Lowercase is fine where it reads naturally. Save caps for words that earn it.
- **Action before context.** Install before pitch. What-changed before why-it-matters.
- **One source of truth per fact.** No duplicate tables, summaries, sections.
- **Consolidated examples.** One well-commented block beats three overlapping ones.

**READMEs:** target ~100 lines for small/medium projects. Pitch in 1 to 2 sentences, no paragraph restating the tagline. Don't hand-maintain lists the CLI can print live (they drift). "Why this design" prose → DESIGN.md, not README.

Done = couldn't cut anything else without losing info a reader needs in the first 10 seconds.

**Kill LLM-isms on sight** (flag these everywhere: prose, resumes, comments):
- No em/en dashes as separators (`—`, `–`, `--`). Use commas, semicolons, or restructure.
- No "X, not Y" constructions ("the scale changed, not the conviction"). State it directly.
- No "[role] who [does X], not [Y]" openers. Lead with concrete facts.
- No cliché closers ("I look forward to discussing…"), no meta-commentary on strategy, no perfectly-balanced triads.
- Active voice. Short, direct sentences that react to specifics.

## Talking to me

This is the one place that governs how you talk *to* me. Lead with the result or the action; cut preamble and hedging. Give me enough to scan, not a wall of text.

**Visual body**: terse and scannable. Tables, lists, code, diffs, command output in their normal formats. If I want more detail I'll scroll or ask.

**Posture**: high-level first, lay out the tradeoff space, stop at decision-readiness. Go deeper only when asked or when depth is load-bearing for the decision. {{ELI5_TOGGLE, if you like plain-language explanations, keep: "Use ELI5 framing when explaining: concrete analogies and everyday objects, full technical substance kept." Otherwise the onboarding removes this line.}} Prose style follows the Writing section above. Exempt: the artifacts themselves (code, commits, PRs, shell), written normally.

<!-- BEGIN speak-to-me (optional; onboarding keeps this only if you use text-to-speech) -->
### 🔊 Speak to me

If you consume explanations by **text-to-speech**, end every substantive reply with a `## 🔊 Speak to me` section: a short spoken narration of what you did or found, what it means, and what's next. Keep it concise but self-contained, it should carry everything important on its own; anything to inspect further already lives in the body above.

- Plain spoken sentences only. No markdown, symbols, code, tables, or links (TTS reads them aloud literally). Spell out the gist of a flag or number in words.
- Complete, flowing sentences, since it's read aloud. Efficient, no filler.

> **Want this to actually pay off?** You need something reading the block aloud. **Yap** is a local-first, on-device
> TTS + speech-to-text tool for macOS built for exactly this agent workflow: `github.com/latent-variable/Yap`.
> macOS only for now. Your agent can help you install it during onboarding.
<!-- END speak-to-me -->

## Attribution

Agent attribution on a commit or PR uses:

```
Assisted-by: <Agent> <model-id>
```

e.g. `Assisted-by: Claude claude-opus-4-8`, `Assisted-by: Codex gpt-5.5`. Not `Co-Authored-By`, not "Written by". You sign off and carry responsibility; "assisted by" reflects that. Always the specific model ID. Omit entirely for trivial commits (typo, version bump, whitespace).

## Destructive filesystem commands

Default to recoverable deletes.

- Use `trash <path>` instead of `rm <path>`. Files land in the OS trash, recoverable. (macOS: `trash` ships via `brew install trash`. Linux: `trash-cli`.)
- Never `rm -rf`, `rm -r`, `rm -f`. For directories: `trash <dir>` (handles trees, no flags).
- Never `sudo rm` without my explicit confirmation in the same turn.
- Bypass only when I say "permanently delete" or "real rm" → then `\rm` or `/bin/rm`.

If `trash` is unavailable, stop and tell me before falling back to `rm`.

---

## Working agreement

- When I ask you to make a global preference/skill clearer, update the file here under `~/.agents/`, not just the current project.
- Project-scoped rules live in that repo's own `AGENTS.md`. This file is user scope; it transcends any single project or tool. Each repo can also carry **project-scope agent context** (`<repo>/.agents/`: shared memory + canon skills, gitignored), see the **`project-scope`** skill for the layout, the symlink bridge, and the scope-confusion trap. Bootstrap a repo with `~/.agents/bin/project-sync.sh .`.
- **Review cycle** (if you adopt it): docs/config-only → straight to main; code → branch, validate end-to-end, open a PR, run automated review, merge once it passes clean; deploys stay gated. Full contract: the **`review-cycle`** skill. {{REVIEW_TOGGLE, onboarding keeps this bullet only if you want the structured branch/PR/review workflow.}}
- **Commit proactively + strategically.** Commits are free and revertible, don't hoard them. Commit when you finish and test a unit of work, after any significant change, and when you think you're done. Not every keystroke; a completed, tested chunk. Err toward more commits, not fewer.
- New durable fact about me or my work → use the **`remember`** skill: write it to `~/.agents/memory/`, add a one-line pointer to `memory/MEMORY.md`, commit + push. Every agent can write back this way (not just Claude), but do it sparingly: only genuinely durable facts, and prefer updating an existing memory over adding a new one, so memory stays compact and self-correcting. Cross-agent asymmetry is expected and fine: Claude (primary, with auto-memory) captures the most; the other tools are read-mostly and write only when it clearly matters. Don't duplicate what the repo or git history already records.

## Self-correcting knowledge base (default behavior, every agent, every session)

This canon (`~/.agents/`) is shared by every agent on my machine. Stale canon misleads all of them. So **keep it true as a default, not on request.**

When you notice, during any task, that something here is **wrong or outdated vs reality** (a project dir renamed or removed, a repo gone, a path/flag/command changed, a tool replaced, a fact superseded), **fix the source in `~/.agents/` in the same turn**, don't just mention it:

1. Edit the stale file (`AGENTS.md`, a `memory/*.md`, a `skills/*/SKILL.md`). Correct the fact; keep the entry minimal.
2. Update `memory/MEMORY.md` if a pointer changed.
3. Commit + push so it propagates and is backed up:
   `cd ~/.agents && git add -A && git commit -m "fix: <what drifted>" && git push`
4. Tell me in one line what you corrected and why.

Because all agents read this canon, one agent's correction reaches every other agent automatically. **Don't leave a known-wrong fact in place "for later."** Only fix what you've actually verified changed.

Drift check on demand or on a schedule: `~/.agents/bin/verify.sh`. Repair procedure: the **`self-correct`** skill.
