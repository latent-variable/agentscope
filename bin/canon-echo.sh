#!/usr/bin/env bash
# Detect user-scope canon restated inside a repo's own agent file.
#
# WHY: a copy of a canon rule is a fork. Canon moves, the copy doesn't, and an
# agent reading the repo obeys the stale copy. Every pattern below is a rule that
# actually drifted in the wild, not a hypothetical.
#
# Usage:
#   canon-echo.sh [path ...]      # default: current directory
#   canon-echo.sh --list          # show what it looks for, and who owns each rule
#
# Exit 0 = clean, 1 = echoes found (advisory: a hit is a prompt to look, not proof).
#
# Legitimate exception? Mark the line and it stops being flagged:
#   <!-- canon-override: <rule> — <why this repo differs> (YYYY-MM-DD) -->
# The marker goes on the line directly above. Keep the override to ONE line of
# what differs; restating the rest of the rule is what this check exists to stop.
set -uo pipefail

# pattern <TAB> what it is <TAB> who owns it
RULES=$(cat <<'EOF'
human-supervised|require(s)? explicit approval|do NOT operate autonomously|explicit (user )?approval before merg|merge only on	merge gate	review-cycle skill
Co-Authored-By	commit attribution	AGENTS.md (Assisted-by)
never mirror work onto the board|human-triggered only	ticket-board posture	trello skill
branch off .?main.*(validate|PR).*(review|merge)|severity.gated loop|zero high/critical.*then merge	the review workflow itself	review-cycle skill
gemini review|Gemini Code Assist	a reviewer that no longer exists	review-cycle skill
never .?rm -rf|trash., never	destructive-delete rule	AGENTS.md
no em.dash|em dashes.* in any	writing rules	AGENTS.md
deploys? (are|stay) gated	deploy gating	review-cycle skill
commit proactively	commit cadence	AGENTS.md
EOF
)

usage_list(){
  printf 'canon-echo.sh looks for these canon rules restated in a repo:\n\n'
  printf '%-38s %s\n' "RULE" "OWNED BY"
  while IFS=$'\t' read -r _pat what owner; do
    [ -z "${what:-}" ] && continue
    printf '%-38s %s\n' "$what" "$owner"
  done <<< "$RULES"
  printf '\nMark a legitimate exception on the line above it:\n'
  printf '  <!-- canon-override: <rule> — <why> (YYYY-MM-DD) -->\n'
}

[ "${1:-}" = "--list" ] && { usage_list; exit 0; }

found=0
scan_file(){
  local f="$1" rel="$2"
  while IFS=$'\t' read -r pat what owner; do
    [ -z "${pat:-}" ] && continue
    # -n gives line numbers so the override marker can be checked on the line above.
    while IFS=: read -r lineno text; do
      [ -z "${lineno:-}" ] && continue
      local prev=""
      [ "$lineno" -gt 1 ] && prev=$(sed -n "$((lineno - 1))p" "$f")
      case "$prev" in *canon-override:*) continue ;; esac
      printf '%s:%s  [%s]\n' "$rel" "$lineno" "$what"
      printf '    %s\n' "$(printf '%s' "$text" | cut -c1-100)"
      printf '    owned by: %s — delete it here, or mark it an override.\n' "$owner"
      found=1
    # Case-insensitive: these rules get restated in prose, so capitalisation
    # varies ("Deploys stay gated" vs "deploys stay gated") and a case-sensitive
    # match silently misses half of them.
    done < <(grep -niE "$pat" "$f" 2>/dev/null)
  done <<< "$RULES"
}

seen=""
for target in "${@:-.}"; do
  for name in AGENTS.md CLAUDE.md Agents.md; do
    f="$target/$name"
    # A symlinked twin (AGENTS.md -> CLAUDE.md) would report the same file twice.
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    # macOS filesystems are case-insensitive, so AGENTS.md and Agents.md can be
    # the SAME file. Dedupe on device+inode, not on the name we happened to try.
    id=$(stat -f '%d:%i' "$f" 2>/dev/null || stat -c '%d:%i' "$f" 2>/dev/null)
    case " $seen " in *" $id "*) continue ;; esac
    seen="$seen $id"
    scan_file "$f" "${target#./}/$name"
  done
done

if [ "$found" = 0 ]; then
  echo "canon-echo: clean"
else
  echo
  echo "canon-echo: a repo file states only what is true of THAT repo. See the project-scope skill."
fi
exit "$found"
