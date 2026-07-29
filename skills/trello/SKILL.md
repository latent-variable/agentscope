---
name: trello
description: >
  Read and actively manage Trello cards from ANY agent, in ANY repo, via the shared `trello` CLI
  (~/.agents/bin/trello). Trello is where the fleet's work is tracked: a board maps to a repo.
  Use this when the user references a card/board, ties work to a ticket, or when you create/manage a
  ticket for real work the agents are doing. Agents create/manage/maintain tickets now; human
  tickets outrank agent ones (agent-made cards carry an "agent" label), and card creation is for
  real units of work, not per-commit noise. Also carries the audience rule: descriptions are the
  agent's spec (detail welcome), comments are a human status update (a few lines, no walls of text).
allowed-tools: Bash, Read
---

# Trello card access (all agents, user scope)

Every agent can read a project's Trello board and actively manage it: create cards, comment,
move them, and shape columns. One shared tool, one shared secret, one board map — all in canon,
so this works from any repo, with no per-project setup.

## The posture that governs everything (shifted 2026-07-05)

**Agents create, manage, and maintain tickets** so the work the fleet actually does is tracked on
the board. This supersedes the old one-way "never create cards" rule. Three things still hold:

- **Human tickets outrank agent tickets.** `add-card` stamps an "agent" label on every card an
  agent creates, so a human sees origin at a glance and can prioritize their own. When you triage
  or order a board, weight human-created cards higher.
- **Track real units of work, not noise.** Create a purposeful ticket (a feature, a bug, a
  shipped fix), never a card per commit or per action. The nightly daemon still does NOT mirror
  every action onto a board; deliberate ticket management is the point, spam is not.
- **Reads are always fine** — look up a board, find a card, quote its state.

When the user names a specific card ("move that ticket to Done"), do exactly that. Otherwise use
judgment to keep the board a true, uncluttered picture of the work.

## Context discipline: read the board narrowly (added 2026-07-28)

Boards grow forever and the finished column ends up being most of them (a real board this was
measured on: 112 of 166 cards are Done). Reading a whole board to answer one question is the main
way Trello wastes an agent's context. Measured there:

| Call | ~tokens | Use when |
|---|---|---|
| `trello find <repo> "<query>"` | ~150-650 | **Default way in.** You know roughly what card you want |
| `trello find <repo> --list "Ready for Agent"` | ~50 | You want one column's working state |
| `trello cards <repo>` (finished column collapsed) | ~1.6k | You need the whole live board |
| `trello show <card>` | ~750 no comments, ~1.1k with 2 | You need ONE card's actual content |
| `trello cards <repo> --all` | ~4.5k | Almost never. Auditing history on purpose |

Rules:

- **Never dump a board to find one card.** `find` takes a name filter and prints one line per hit.
- **`cards` hides the finished column by default** and prints `# hidden: Done (112)`. That is
  correct behavior, not missing data. Reach for `--list Done` or `--all` only when the question is
  actually about completed work.
- **`show` is the only right way to read a card body.** It prints title, column, labels,
  description, and the newest comments as plain text, truncating long ones. Do NOT curl the Trello
  API for a card: raw JSON costs roughly double for the same words and buries the description in
  fields nobody reads. `--comments 0` for description only, `--full` to defeat truncation.
- **One read per question.** If `find` gave you the URL and the title answers the question, stop.
  Only `show` the card when you need the spec or the history.

## Who each field is written for (added 2026-07-28)

A card has two audiences and they want opposite things. Get this backwards and the board turns
into a wall of text nobody reads.

| Field | Audience | Bar |
|---|---|---|
| **Title** | human, scanning | one line, states the problem, no preamble |
| **Description** | the AGENT that will do the work | detailed is good. It is the spec |
| **Comment** | the human, checking the board | a few lines. Status, not a report |

**Description = spec.** Write it for whoever picks the card up. Root cause, constraints, the
options with tradeoffs, files, prior evidence, what "done" means. Length is fine here because a
machine is going to act on it and every detail you cut is a detail it has to rediscover. When an
investigation changes the plan, **edit the description** so the spec stays true (`trello edit-card
<url> --desc`), don't bolt the new understanding onto the end of a comment thread.

**Comment = status.** A human reads these. Nobody reads a 3000-character investigation log, and
posting one buries the one sentence that mattered. Target **under ~5 lines**, and lead with the
line that changes what they do next.

Cover only:
1. **What changed** (confirmed, fixed, blocked, shipped).
2. **What it means**, if that is not obvious from #1.
3. **What they have to decide or approve**, if anything.
4. **A link** to where the detail lives (PR, commit, the card's own description).

Leave out: how you investigated, evidence dumps, test counts, file/function names, library
versions, per-bullet change lists, hedged side-observations, anything you already fixed. That
material belongs in the PR, the commit message, or the description. A comment points at it.

```
# Too long (real example, 3048 chars): probe methodology, per-field change list, 17 tests,
# an n=10 side-correlation, all in a comment.

# Right:
trello comment <url> "Confirmed: telemetry bug, not a search bug. The model searched on 10/10
cells; we were only counting cells that also returned citation chunks, so ~half of every
landscape got marked untrustworthy for no reason. Fixed in PR #214, 185 tests green.
Nothing needed from you. Detail in the PR."
```

Same discipline as the READMEs-vs-AGENTS.md split in canon: the human gets oversight, the agent
gets the minutia. **Applies to every agent writing to a board, including the nightly fleet.**

## The CLI

```
# Cards
trello boards                       # repo -> board map (what's wired)
trello cards <board|repo> [--list <col>] [--all]   # board by column; finished column collapsed to a count
trello find  <repo> [query] [--list <col>]        # find cards by name (cheapest way in)
trello show  <cardUrl|id> [--comments N] [--full] # ONE card: description + newest comments, as text
trello add-card <board> "<title>" [--desc <t>] [--list <col>]  # create a card (marked 'agent'; default column Backlog)
trello edit-card <cardUrl|id> [--title <t>] [--desc <t>]  # edit a card's title/description
trello archive-card <cardUrl|id>    # archive a card (reversible in the UI)
trello comment <cardUrl|id> "text"  # add a comment to a card
trello move    <cardUrl|id> <list> [board]  # move to a list; pass a board to transfer across boards

# Labels
trello labels <board|repo>          # a board's labels: color, name, use count
trello label <cardUrl|id> <name> [--color <c>]  # add a label (creates it on the board if new)
trello unlabel <cardUrl|id> <name>  # remove a label from a card

# Board management (structure, not cards)
trello create-board "<name>" [--desc <t>]  # new board with the standard columns
trello lists <board|repo>           # a board's columns
trello add-list <board> <name>      # add a column
trello rename-list <board> <o> <n>  # rename a column
trello archive-list <board> <name>  # archive an (emptied) column
trello standardize <board|repo>     # bring a board up to the standard columns (below)
```

- **Board/repo** accepts a board name (`Website`), a repo slug (`your-org/your-repo`),
  a repo basename (`your-repo`), or a boardId (a raw boardId works even before the board is
  wired into the map, so a freshly created board is usable immediately).
- **Card ref** accepts a full card URL, its shortlink, or its id.
- **List names** are the board's own; on a standardized board that's `Backlog`, `Ready for Agent`,
  `In Progress`, `Testing`, `Complete`. `Complete` lands at the top so newest-done stays visible.

After `create-board`, wire it: add an entry to `~/.agents/trello-boards.json` so `trello <repo>`
resolves it by name. `add-card` marks every card with the "agent" label; create tickets for real units of work, and weight
human-created cards higher when you triage.

Typical flow when the user ties work to a ticket:
1. `trello find <repo> "<keywords>"` → get the card URL if you don't have it.
2. Do the work.
3. `trello comment <cardUrl> "Shipped in <PR/commit>."` and/or `trello move <cardUrl> Complete`.

## Labels (two axes)

Use labels on two axes; mirror whatever the board already does. Check a board's existing
palette first (`trello labels <board>`) and REUSE its names, don't invent parallel ones.

- **Type / guidance** (what kind of work): `Feature 🆕` (green), `Bug`, `Refactor`, `Enabler`,
  `EPIC` (red_light, a major initiative that groups other cards), `High Priority` (red_dark),
  `Security`. Emoji in a name is intentional (`Feature 🆕`, `Admin 🎟️`); keep it.
- **Component / feature tag** (what major area it touches): per-project. On a tooling board that
  is its subsystems (`Reviewer`, `Auditor`, `Orchestrator`); on a product board it is
  `UI`/`Backend`/`Payment`/`API` etc. These are what make it easy to see everything tied to one
  major effort.

A good card carries ONE component tag + one type tag (plus `agent` if an agent made it). Apply
with `trello label <cardUrl> <name> --color <c>` (color only matters on first create).

## Board standard (user scope)

Every board is expected to have these columns, left-to-right (encoded as `STANDARD_LISTS` in the
CLI — the single source of truth; `trello standardize <board>` enforces it):

| Column | Meaning |
|---|---|
| **Backlog** | Human triage — ideas/requests not yet ready for an agent |
| **Ready for Agent** | Intake signal. Human-triaged and ready for an agent to pick up |
| **In Progress** | Actively worked (issue open / PR in flight) |
| **Testing** | PR up / under review / validating |
| **Complete** | Shipped/merged. Completion write-back goes to the TOP here |

`standardize` is additive and idempotent: it creates missing columns, renames known aliases
(`Doing`→`In Progress`, `Done`→`Complete`, `Testing/Reviewing`→`Testing`), orders the standard
block to the front, and **never deletes a board's own extra columns**. So a project keeping extra
columns (e.g. `Bugs`, `Discussion`) is fine — those live past the standard block.

**Scope split:** the standard columns above are the user-scope baseline every board meets.
**Per-project specifics live in project scope** — which board this repo ties to, and any extra
columns particular to that board — in the repo's own `AGENTS.md` / `.agents/`.

## Where the pieces live

| Piece | Location |
|---|---|
| CLI | `~/.agents/bin/trello` |
| Secret (key+token) | `~/.agents/secrets/trello-auth.json` — gitignored, **never commit or echo it** |
| Board map (CLI source of truth) | `~/.agents/trello-boards.json`, keyed by repo |

**Auth file** (`{"key","token"}`): create an API key + token at https://trello.com/power-ups/admin.
Keep the file gitignored; the CLI sends both in an OAuth header, never in a URL.

**Board map** is a hand-edited JSON file:

```json
{ "boards": [ { "board": "Website", "repo": "your-org/your-repo", "boardId": "6…" } ] }
```

Override either path with `$AGENTS_TRELLO_AUTH` / `$AGENTS_TRELLO_BOARDS`.

## Which board is "this repo"?

An agent working in a repo finds its board by repo name: `trello cards <repo-basename>`. Each mapped
repo's own tracked `AGENTS.md` also carries a one-line signpost ("Trello board: …"). If a repo has no
board in `trello boards`, it simply isn't wired to Trello yet — don't invent one.
