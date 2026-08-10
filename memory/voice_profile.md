---
name: Voice Profile
description: How the user actually sounds. Measured register, verbal tics, what must survive editing, and the dated log of real edits they made to agent drafts. Read before drafting anything sent under their name.
metadata:
  type: user
---

<!-- TEMPLATE. The `voice` skill fills and extends this. Everything below is a placeholder.
     Do NOT invent entries: a row here is only worth having if it came from a measurement or
     from a real edit the user made. An empty section is honest; a guessed one is worse than
     nothing, because it will be trusted. -->

The always-on writing bans (dashes, LLM-isms, sign-off, fenced blocks) live in `~/.agents/AGENTS.md`.
This file holds what is **measured**, not what is preferred. The `voice` skill holds the procedure.

## Register (measured, not guessed)

Run the corpus recipe in the `voice` skill (§1) and record the numbers here.

- **Median sentence length:** {{n}} words
- **Mean:** {{n}} words. **Over 25 words:** {{n}}%
- **Sample size:** {{n}} dictated turns, measured {{YYYY-MM-DD}}
- **Reading:** {{one line, e.g. "short declaratives; long turns are dictation and get cut in editing"}}

## Vocabulary and construction

- **Everyday words over literary ones.** Never out-literate the user.
- {{words and constructions they actually use}}
- {{words and constructions they never use}}

## Input-only tics

Speech habits that appear when the user dictates and must **not** be reproduced in writing.
Dictation is input; the profile is the target.

- {{e.g. filler openers, repeated phrases, self-interruptions}}

## What must survive editing

Things that look like flaws and are not. Do not "fix" these.

- {{e.g. their own wording, used near-verbatim}}
- {{e.g. a plain contrast that carries real information}}

## Correction log

The highest-value section, and the only one that cannot be guessed. One row per **real edit the
user made to an agent draft**. What they removed matters more than what they asked for: removals
reveal instincts they have never articulated.

| Date | What the agent wrote | What they changed it to | The rule it implies |
|------|----------------------|-------------------------|---------------------|
| {{YYYY-MM-DD}} | {{the draft line}} | {{their line}} | {{the generalisation}} |
