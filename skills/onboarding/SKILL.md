---
name: onboarding
description: >
  First-run setup for agentscope. Interview the user, fill the AGENTS.md template + memory with their
  identity and preferences, detect which agent CLIs are installed, wire them all to ~/.agents, and tune
  optional features (ELI5 explanations, the Speak-to-me TTS block, the review-cycle workflow). Run this
  the first time someone clones agentscope, or when they say "onboard me" / "set up agentscope".
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Onboard a new user to agentscope

Goal: turn the shipped **template** into *this person's* user-scope brain, and wire every agent CLI on their
machine to it. After this, every tool (Claude, Codex, Gemini/Antigravity, Pi) reads the same identity,
preferences, skills, and memory. Be warm and quick — this is someone's first impression of the system.

## 0. Detect state first (don't re-onboard a configured user)

```bash
ls -d ~/.agents 2>/dev/null || echo "NOT INSTALLED at ~/.agents"
grep -l '{{' ~/.agents/AGENTS.md 2>/dev/null && echo "TEMPLATE still has placeholders → onboard"
```

- If `~/.agents` doesn't exist: the repo was cloned elsewhere. Tell them to `git clone ... ~/.agents` (or move it), then re-run.
- If `AGENTS.md` has no `{{...}}` markers: already onboarded. Confirm and offer to re-wire (`bin/sync.sh`) or edit a specific preference instead.

Detect installed CLIs (only these get wired):

```bash
for d in .claude .codex .gemini .pi; do [ -d "$HOME/$d" ] && echo "found: ~/$d"; done
```

## 1. Interview (keep it short — 6 quick prompts, conversational)

Ask these, adapting to what they volunteer. Don't interrogate; one message with the list is fine.

1. **Who are you?** Name + a sentence or two: role, background, what you build. (→ bio + `user_profile.md`)
2. **Where does your work live?** Top project directories (e.g. `~/Documents/...`, `~/Code/...`) + GitHub handle. (→ "Where my work lives")
3. **Explanation style — do you want ELI5?** Plain-language analogies layered on top of full technical substance, or straight technical only? (→ keeps/strips the ELI5 line)
4. **Spoken summaries?** Do you use (or want) text-to-speech reading a short "here's what I did" at the end of each reply? (→ keeps/strips the **🔊 Speak to me** block). If yes and they're on **macOS**, mention **Yap** (`github.com/latent-variable/Yap`) — local-first on-device TTS+STT built for this — and offer to help install it (§4).
5. **Workflow — structured review cycle?** Do you want agents to branch / open PRs / run automated review before merging code, or keep it lightweight? (→ keeps/strips the review-cycle bullet)
6. **Attribution name** for commits (defaults to "Claude" / the agent's own name + model id). Most people keep the default.

## 2. Fill the template

Edit `~/.agents/AGENTS.md` — replace every `{{...}}` block:

- `{{YOUR_NAME}}` in the title and "Who I am" → their name + bio paragraph.
- `{{BIO ...}}` → the one-paragraph bio.
- `{{PROJECT_DIRS ...}}` → their actual dirs + `GitHub: <handle>`.
- `{{ELI5_TOGGLE ...}}` → if yes, replace with the literal sentence: `Use ELI5 framing when explaining: concrete analogies and everyday objects, full technical substance kept.` If no, delete the toggle text (leave the surrounding sentence clean).
- `{{REVIEW_TOGGLE ...}}` → if they want it, delete just the brace note (keep the bullet). If not, delete the whole review-cycle bullet.

**Speak-to-me block** (between `<!-- BEGIN speak-to-me -->` and `<!-- END speak-to-me -->`):
- TTS **yes** → keep the block; delete the two HTML comment markers so it reads clean. Keep the Yap pointer only on macOS.
- TTS **no** → delete the entire block including both markers.

Verify nothing is left: `grep -n '{{' ~/.agents/AGENTS.md` must return nothing.

## 3. Seed memory

- Write `~/.agents/memory/user_profile.md` from the bio (use the `remember` skill's format: frontmatter + body). Fill the template that ships there.
- Add/confirm the one-line pointer in `~/.agents/memory/MEMORY.md`.
- If they gave project dirs worth pinning, optionally seed `memory/reference_project_dirs.md` too.

## 4. (macOS + TTS only) Offer Yap

Only if they said yes to spoken summaries and are on macOS:

```bash
# Public, MIT-licensed. Easiest install is Homebrew; or DMG from releases; or build from source.
echo "Yap: local-first on-device TTS + STT for macOS — github.com/latent-variable/Yap"
echo "  brew install --cask latent-variable/tap/yap   # or grab a DMG from /releases"
```

Offer to walk them through install. Don't block onboarding on it — note it and move on if they defer.

## 5. Wire every installed CLI

```bash
~/.agents/bin/sync.sh
~/.agents/bin/sync.sh --check
```

`sync.sh` only touches tools it finds; it backs up anything real it replaces into `~/.agents/backups/`.

## 6. Back it up (recommended)

Encourage them to make `~/.agents` their own **private** repo so canon is versioned + backed up, and so the
self-correcting loop has somewhere to push:

```bash
cd ~/.agents && git add -A && git commit -m "onboarding: my user scope" && git push   # after they add a remote
```

## 7. Verify + hand off

```bash
~/.agents/bin/verify.sh
```

Then a short confirmation: who you recorded them as, which CLIs you wired, which optional features are on
(ELI5, Speak-to-me, review-cycle), and the two things they control going forward —
edit `AGENTS.md` for global behavior, drop facts via the `remember` skill. Point them at the other skills
by name so they know what's available.
