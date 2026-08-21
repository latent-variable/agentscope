#!/usr/bin/env bash
# Meter the ALWAYS-ON agent context and report what to cut when it grows past budget.
#
# WHY: skills, memory bodies and DESIGN.md are loaded on demand, so their size is
# nearly free. AGENTS.md and a MEMORY.md index are pasted into EVERY request by
# EVERY agent, so a char added there is paid on every turn forever. Nothing was
# measuring that, and it grows monotonically because each addition is individually
# reasonable. A single project AGENTS.md in the wild reached 242,845 chars (~61k
# tokens, ~23% of a 262k window) before anything reported it.
#
# The tool measures; it does not judge WHAT belongs. That rule is one line:
#   always-on carries the TRIGGER, on-demand carries the PROCEDURE and the EVIDENCE.
# A rule an agent must obey before it knows it needs to look something up stays.
# Its case study, its rationale and its steps move to a skill or a memory file,
# with a pointer left behind. See the `project-scope` and `cleanup` skills.
#
# Usage:
#   canon-size.sh                 # user scope + the repo in the current directory
#   canon-size.sh --user          # user scope only (what verify.sh calls)
#   canon-size.sh --skills        # every skill against its own budget
#   canon-size.sh <path> [...]    # named repos
#   canon-size.sh --all           # user scope + every checkout under the known roots
#   canon-size.sh --breakdown <file>   # section sizes for one file, biggest first
#   canon-size.sh --budgets       # show the budgets and how to override them
#
# Exit 0 = everything inside budget, 1 = something is over.
set -uo pipefail

# Budgets in CHARS (~4 chars per token). Override any of them in the environment.
# They are deliberately below Claude Code's own 150,000-char complaint: by the time
# a harness warns, every agent has already been paying for months.
BUDGET_USER_CANON="${CANON_BUDGET_USER_CANON:-40000}"   # ~/.agents/AGENTS.md
BUDGET_USER_INDEX="${CANON_BUDGET_USER_INDEX:-12000}"   # ~/.agents/memory/MEMORY.md
BUDGET_REPO_CANON="${CANON_BUDGET_REPO_CANON:-30000}"   # <repo>/AGENTS.md
BUDGET_REPO_INDEX="${CANON_BUDGET_REPO_INDEX:-8000}"    # <repo>/.agents/memory/MEMORY.md
BUDGET_SESSION="${CANON_BUDGET_SESSION:-100000}"        # user + repo, what a session starts with
# A skill is on-demand, so it can be bigger than an always-on file — but only up to a
# point. A skill you open for nearly every task is paid for nearly every task,
# which makes it always-on in practice even though it loads on demand. Meter it.
#
# The ceiling is a decision, not a tuning knob: if a skill does not fit, the first
# move is to push EVIDENCE (case studies, war stories, worked examples) out to
# skills/<name>/references/ and keep the contract in SKILL.md. Raise the number
# only when what does not fit is genuinely contract. One real skill went 37,684 ->
# 14,875 chars on that split alone, losing nothing an agent needed to obey it.
BUDGET_SKILL="${CANON_BUDGET_SKILL:-25000}"             # one skills/*/SKILL.md
WARN_PCT="${CANON_WARN_PCT:-80}"                        # WARN at this % of budget

AGENTS="${AGENTS_DIR:-$HOME/.agents}"
# Where checkouts live. Same roots the cleanup skill sweeps.
# Where your checkouts live. Override with CANON_ROOTS="dir1 dir2 ..." — the
# default is deliberately one directory, because guessing at someone else's
# layout and silently scanning nothing is worse than scanning one obvious place.
ROOTS="${CANON_ROOTS:-$HOME/Documents}"

over=0
C_RED=$'\033[0;31m'; C_YEL=$'\033[1;33m'; C_GRN=$'\033[0;32m'; C_OFF=$'\033[0m'
[ -t 1 ] || { C_RED=""; C_YEL=""; C_GRN=""; C_OFF=""; }

commas(){ printf '%s' "$1" | awk '{ n=$0; s=""; while (length(n)>3) { s=","substr(n,length(n)-2)s; n=substr(n,1,length(n)-3) } print n s }'; }
tokens(){ awk -v c="$1" 'BEGIN{ t=c/4; if (t<1000) printf "%d", t; else printf "%.1fk", t/1000 }'; }

# BSD and GNU stat differ. Probe -c FIRST, because it is the only option of the
# two that is unambiguous: BSD stat has no -c at all, while `-f` means "format" on
# BSD and "filesystem status" on GNU, so probing -f first reads a signal that means
# two different things. -L FOLLOWS the link: CLAUDE.md is normally a symlink to
# AGENTS.md, and without -L the link and its target report different inodes, so the
# same canon gets billed twice.
if   stat -L -c '%d:%i' . >/dev/null 2>&1; then stat_id(){ stat -L -c '%d:%i' "$1" 2>/dev/null; }
elif stat -L -f '%d:%i' . >/dev/null 2>&1; then stat_id(){ stat -L -f '%d:%i' "$1" 2>/dev/null; }
else
  # No usable stat. Fall back to the PATH, so nothing dedupes and the twin is
  # billed twice. A meter that reads HIGH is annoying; one that reads LOW is
  # useless, and a constant id here would silently omit every file after the first.
  stat_id(){ printf '%s' "$1"; }
fi

# Section sizes, biggest first. A file is cut by section, so this is the actual
# work list: the top two or three entries are almost always the whole overage.
breakdown(){
  local f="$1" level="${2:-## }" n="${3:-8}"
  awk -v lvl="$level" '
    index($0, lvl) == 1 && substr($0, length(lvl)+1, 1) != "#" {
      if (name != "") printf "%d\t%s\n", size, name
      name = substr($0, length(lvl)+1); size = 0; next
    }
    { size += length($0) + 1 }
    END { if (name != "") printf "%d\t%s\n", size, name }
  ' "$f" | sort -rn | head -"$n" | while IFS=$'\t' read -r size name; do
    printf '         %9s  %s\n' "$(commas "$size")" "$(printf '%s' "$name" | cut -c1-70)"
  done
}

longest_lines(){
  awk '{ printf "%d\t%s\n", length($0), $0 }' "$1" | sort -rn | head -8 \
    | while IFS=$'\t' read -r len text; do
        printf '         %9s  %s\n' "$(commas "$len")" "$(printf '%s' "$text" | cut -c1-70)"
      done
}

# One always-on file: measure, classify, and if it is over, show where the mass is.
row(){
  local f="$1" budget="$2" label="$3" chars pct status color
  [ -f "$f" ] || return 0
  chars=$(wc -c < "$f" | tr -d ' ')
  pct=$(( chars * 100 / budget ))
  # OVER is decided on the raw chars, never on pct. Integer division truncates, so
  # 40,001 against a 40,000 budget computes 100 and would report WARN — the meter
  # reading LOW while the board stays green, which is the one failure that matters.
  # pct is for display only.
  if   [ "$chars" -gt "$budget" ];  then status=OVER; color="$C_RED"; over=1
  elif [ "$pct" -ge "$WARN_PCT" ];  then status=WARN; color="$C_YEL"
  else status=ok; color="$C_GRN"; fi
  printf '  %s%-4s%s %10s  %6s  %4s%%  %s\n' \
    "$color" "$status" "$C_OFF" "$(commas "$chars")" "$(tokens "$chars")" "$pct" "$label"
  if [ "$status" = OVER ]; then
    local detail; detail="$(breakdown "$f")"
    if [ -n "$detail" ]; then
      printf '       biggest sections:\n%s\n' "$detail"
    else
      # A MEMORY.md index has no headings — it is one bullet per memory. There the
      # cut signal is a pointer that grew into a paragraph, so rank by line length.
      printf '       longest lines (an index entry should be one line, not a summary):\n'
      longest_lines "$f"
    fi
  fi
  SCOPE_CHARS=$(( SCOPE_CHARS + chars ))
  return 0
}

# A repo's always-on set. AGENTS.md and CLAUDE.md are usually the same inode
# (symlinked twins) — counting both would double the bill on paper.
scope_repo(){
  local dir="$1" name canon="" id seen="" f
  name="$(basename "$dir")"
  SCOPE_CHARS=0
  for f in "$dir/AGENTS.md" "$dir/CLAUDE.md"; do
    [ -f "$f" ] || continue
    id=$(stat_id "$f")
    case " $seen " in *" $id "*) continue ;; esac
    seen="$seen $id"
    canon="$f"
    row "$f" "$BUDGET_REPO_CANON" "$name/$(basename "$f")"
  done
  [ -n "$canon" ] || return 0
  row "$dir/.agents/memory/MEMORY.md" "$BUDGET_REPO_INDEX" "$name/.agents/memory/MEMORY.md"
  REPO_CHARS="$SCOPE_CHARS"
}

usage_budgets(){
  printf 'Budgets in chars (~4 chars/token). Override in the environment:\n\n'
  printf '  %-28s %9s  %s\n' "CANON_BUDGET_USER_CANON"  "$BUDGET_USER_CANON"  '~/.agents/AGENTS.md'
  printf '  %-28s %9s  %s\n' "CANON_BUDGET_USER_INDEX"  "$BUDGET_USER_INDEX"  '~/.agents/memory/MEMORY.md'
  printf '  %-28s %9s  %s\n' "CANON_BUDGET_REPO_CANON"  "$BUDGET_REPO_CANON"  '<repo>/AGENTS.md'
  printf '  %-28s %9s  %s\n' "CANON_BUDGET_REPO_INDEX"  "$BUDGET_REPO_INDEX"  '<repo>/.agents/memory/MEMORY.md'
  printf '  %-28s %9s  %s\n' "CANON_BUDGET_SKILL"       "$BUDGET_SKILL"       'one skills/*/SKILL.md'
  printf '  %-28s %9s  %s\n' "CANON_BUDGET_SESSION"     "$BUDGET_SESSION"     'user + repo, per session'
  printf '  %-28s %9s  %s\n' "CANON_WARN_PCT"           "$WARN_PCT"           'warn at this % of budget'
  printf '\nOn-demand files (skills, memory bodies, DESIGN.md, docs/) are NOT metered.\n'
  printf 'Moving content there is the fix, not a way to game the number.\n'
}

case "${1:-}" in
  --budgets) usage_budgets; exit 0 ;;
  --skills)
    printf '== skills (on demand, but a skill loaded on most tasks is a second always-on file) ==\n\n'
    printf '  %-4s %10s  %6s  %5s  %s\n' "" "CHARS" "~TOK" "OF BGT" "SKILL"
    SCOPE_CHARS=0
    for sk in "$AGENTS"/skills/*/SKILL.md; do
      [ -f "$sk" ] || continue
      row "$sk" "$BUDGET_SKILL" "$(basename "$(dirname "$sk")")"
    done
    printf '\n  %s chars across %s skills\n' "$(commas "$SCOPE_CHARS")" "$(ls -d "$AGENTS"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')"
    [ "$over" -eq 0 ] && printf '\ncanon-size: skills within budget\n' \
      || printf '\ncanon-size: a skill is over. Move the evidence to skills/<name>/references/,\n  which loads only when an agent actually needs it, and keep the contract here.\n'
    exit "$over" ;;
  --breakdown)
    [ -f "${2:-}" ] || { echo "canon-size: --breakdown needs a file" >&2; exit 2; }
    printf '%s — %s chars, ~%s tokens\n\n' "$2" "$(commas "$(wc -c < "$2" | tr -d ' ')")" "$(tokens "$(wc -c < "$2" | tr -d ' ')")"
    printf '  ## sections\n'; breakdown "$2" '## ' 100
    printf '\n  ### sections\n'; breakdown "$2" '### ' 15
    exit 0 ;;
esac

printf '== always-on context (loaded on every turn, by every agent) ==\n\n'
printf '  %-4s %10s  %6s  %5s  %s\n' "" "CHARS" "~TOK" "OF BGT" "FILE"

SCOPE_CHARS=0
row "$AGENTS/AGENTS.md"        "$BUDGET_USER_CANON" "user: AGENTS.md"
row "$AGENTS/memory/MEMORY.md" "$BUDGET_USER_INDEX" "user: memory/MEMORY.md"
USER_CHARS="$SCOPE_CHARS"

targets=()
case "${1:-}" in
  --all)
    # A linked worktree has a .git FILE, not a directory. Metering it reports the
    # same canon twice under a name that looks like a separate repo.
    for r in $ROOTS; do
      [ -d "$r" ] || continue
      if [ -d "$r/.git" ]; then targets+=("$r"); continue; fi
      for d in "$r"/*/; do [ -d "${d}.git" ] && targets+=("${d%/}"); done
    done ;;
  # --user is what verify.sh calls: user scope only, regardless of where it runs
  # from. Without it, verify.sh invoked inside a repo would fail its own board on
  # that repo's file, which is not ~/.agents' business.
  --user) : ;;
  "") [ -d "./.git" ] && targets+=("$(pwd)") ;;
  *)  targets=("$@") ;;
esac

for t in "${targets[@]:-}"; do
  [ -n "$t" ] && [ -d "$t" ] || continue
  REPO_CHARS=0
  scope_repo "$t"
  [ "$REPO_CHARS" -eq 0 ] && continue
  total=$(( USER_CHARS + REPO_CHARS ))
  pct=$(( total * 100 / BUDGET_SESSION ))
  # Raw compare, same reason as in row(): pct truncates and would let a session
  # one char over the budget report 100% and pass.
  if [ "$total" -gt "$BUDGET_SESSION" ]; then color="$C_RED"; over=1
  elif [ "$pct" -ge "$WARN_PCT" ]; then color="$C_YEL"; else color="$C_GRN"; fi
  printf '  %s%-4s%s %10s  %6s  %4s%%  %s\n' "$color" "SESS" "$C_OFF" \
    "$(commas "$total")" "$(tokens "$total")" "$pct" "→ a session in $(basename "$t") starts here"
done

printf '\n'
if [ "$over" -eq 0 ]; then
  printf 'canon-size: within budget\n'
else
  printf 'canon-size: over budget. Cut by section (biggest first, listed above).\n'
  printf '  Keep in AGENTS.md: the rule, in one or two sentences, plus where to look.\n'
  printf '  Move out: case studies, procedures, war stories, anything an agent only\n'
  printf '  needs once it has decided to do the thing. A pointer costs one line.\n'
  printf '  Detail for one file:  canon-size.sh --breakdown <file>\n'
fi
exit "$over"
