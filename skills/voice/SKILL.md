---
name: voice
description: >
  Write in the user's voice, and keep discovering what that voice is. Load before drafting anything
  that goes out under their name (email, DM, recruiter reply, LinkedIn, README, PR body, resume
  line, client-facing copy), and when they ask to work on their writing voice or authorship. Holds
  the drafting loop, the send test, and the discovery procedure that mines their real corpus for
  traits no style rule predicts.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

# Voice: authorship, not anti-slop

## Where things live

| What | Where |
|---|---|
| The always-on bans (dashes, LLM-isms, efficiency-framing tic, sign-off, fenced blocks) | Writing section of `~/.agents/AGENTS.md` |
| The measured voice facts: register, tics, correction log, samples | `~/.agents/memory/voice_profile.md` |
| How to draft, and how to extend the profile | this file |
| Casual replies on GitHub/forums | `draft-response` skill (lowercase-casual register, a different surface) |
| Explanation depth | `eli5` skill and `feedback_explain_simply` |

Read `voice_profile.md` before drafting. It is short and it is the actual spec.

## Why a banned-phrase list is not enough

This is the part worth understanding, because it explains why every public anti-slop skill
plateaus.

A model is trained toward one broadly-rewarded idea of good writing: clear, confident,
complete, professional. That target is genuinely useful for code and for docs. It is the
wrong target for authorship, because authorship has no single correct answer. Every model
climbing the same hill is why the same rhythms, the same headings, the same dramatic contrast
show up everywhere.

Now add a shared banned-phrase list on top. If everyone bans the same words and strips the
same punctuation, the models converge on a *different* shared hill and we meet at the top
again. The list is necessary and it is not sufficient. **The only thing that does not
converge is evidence about one specific person**, which is why this skill's real work is the
discovery procedure at the bottom, and why the profile is built from measurements and from
their own edits rather than from taste rules.

Credit where due: this framing comes from a Nate B. Jones video on authorship vs slop.

## The two tests before anything is sent

**Did you read it?** Not generated it. Read it, start to finish, as the recipient.

**Do you mean it?** Every claim in it is one the user would defend if challenged.

Fail either one and it does not go out. Slop does not remove work, it moves the work onto the
reader. A paragraph nobody checked is worse than a wrong paragraph, because it spends someone
else's attention to find out.

## The drafting loop

Good writing takes many passes, and it did before AI. AI makes each pass faster; it does not
replace the passes. So do not hand over a first draft and call it done.

1. **Say the point in one sentence, to yourself, before writing.** If you cannot, you do not
   know what the message is yet, and no amount of polish will fix that.
2. **Draft it long.** Get the content down without editing.
3. **Cut every sentence that neither asks, states, nor decides.** This single pass removes
   most of what they would have removed. See the three shapes in the correction log:
   the paragraph that says "no change," the trailing justification, the stacked second ask.
4. **Cut the connective tissue.** Any clause that exists to make the next clause feel
   reasonable. Lead with the real point instead.
5. **Check register against the profile.** Plain words, short sentences, concrete nouns. Do
   not out-literate them. Do not mimic their dictation either.
6. **Read it aloud as the recipient.** Anything that sounds like a person performing
   reasonableness gets cut.
7. **Hand it over in a fenced code block** if they are going to paste it.

When they give you their own wording, use it near-verbatim. Fix obvious speech-to-text
artifacts, never the register.

## Judging a draft

Four questions, in order. The first failure is the one to fix.

1. **What is it asking for?** If you cannot name one action, there is no message.
2. **What could be deleted with no loss?** Delete it now.
3. **Would a stranger know a human decided this?** A draft with no decision in it reads as
   generated no matter how clean the prose is.
4. **Does it sound like them, or like a competent writer?** The second is the failure mode
   that survives every checklist.

## Discovery: finding what is not written down yet

Run this when they ask to work on their voice, when a draft misses in a way the profile does not
explain, or every few months. The output is edits to `voice_profile.md`, never a new file.

**Voice lives in deltas, not in samples.** Three deltas are available, in increasing value:

### 1. Register, from the dictation corpus

Their session transcripts are hundreds of thousands of words of unguarded speech. Measure, do
not eyeball. The recipe that produced the current numbers:

```bash
python3 - <<'PY'
import json,glob,re,statistics
msgs=[]
for f in glob.glob('/Users/linovaldovinos/.claude/projects/**/*.jsonl',recursive=True):
    for line in open(f,errors='ignore'):
        try: d=json.loads(line)
        except: continue
        if d.get('type')!='user': continue
        c=d.get('message',{}).get('content')
        if isinstance(c,str): msgs.append(c)
# a dictated turn: no code fence, no diff, no tool wrapper, reads as speech
bad=re.compile(r'```|^\s*[+-]{2,}|<system-reminder|<local-command|<command-|Caveat:|^\s*\{|\$\(|=>')
speech=re.compile(r"\b(I|I'm|I've|we|let's|okay|yeah)\b")
d=[m for m in msgs if not bad.search(m) and speech.search(m) and len(m.split())>=12]
sents=[s for m in d for s in re.split(r'(?<=[.!?])\s+',m) if s.split()]
L=[len(s.split()) for s in sents]
print(len(d),"turns |median",statistics.median(L),"|mean",round(statistics.mean(L),1),
      "|>25w %.0f%%"%(100*sum(x>25 for x in L)/len(L)))
PY
```

The filter is imperfect: some pasted prose survives. Say so when reporting, and use the
numbers as direction rather than precision.

### 2. Corrections, from canon history

Every dated feedback entry in `~/.agents/AGENTS.md` and `memory/feedback_*.md` is a record of
a real edit they made to an agent draft.

```bash
cd ~/.agents && git log --follow -p --since='6 months ago' -- AGENTS.md \
  | grep -E '^\+' | grep -iE 'writ|voice|say|word|tone|sound|draft|cut'
```

**What they removed is worth more than what they asked for**, because removals reveal instincts
they have never articulated. Every entry in the correction log came from one of these.

### 3. Rewrites, the highest-value source

When they take a draft and change it before sending, that diff is the purest signal available.
Capture it while it is in front of you: the before, the after, and one line on what the change
was doing. Add it to the correction log the same turn. These decay fast, so do not defer.

### Writing a finding down

A finding earns a row only if it is **specific, evidence-backed and actionable**. "They like
concise writing" is none of those. "They cut the clause after the comma when it justifies the
recommendation, 2026-07-31" is all three.

Prefer editing an existing row over adding one. The profile stays compact or it stops being
read, which defeats the whole thing.

## Landing it

Profile and skill edits are docs work: commit and push to `main` in the same turn, no branch,
no PR.

```bash
cd ~/.agents && git add -A && git commit -m "voice: <what you learned>" && git push
```

## Do not

- Do not paste the always-on bans into this file or the profile. They live in `AGENTS.md`.
  A copy forks and goes stale.
- Do not invent a trait. Every line in the profile traces to a measurement or a dated edit.
- Do not mimic their dictation. The transcript is input; the profile is the target.
- Do not send a draft you have not read as the recipient.
- Do not let a clean checklist pass stand in for having a point.
