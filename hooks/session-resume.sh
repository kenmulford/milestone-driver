#!/usr/bin/env bash
# milestone-driver - session-resume hook (Claude SessionStart, matcher: compact)
#
# Re-injects the milestone run's wave-state checkpoint after Claude Code
# auto-compacts context mid-run, so the orchestrator resumes from what is
# already on disk instead of re-probing every dispatched issue
# (skills/solve-milestone/parallel-waves.md (Wave-state checkpoint - consult
# before probing)).
#
# Input field used (SessionStart hook stdin, verified at
# https://code.claude.com/docs/en/hooks): `cwd` only. The "which matcher
# fired" question ("compact" vs "startup"/"resume"/"clear"/"fork") is answered
# by Claude Code itself via hooks.json's `matcher` field before this script
# ever runs - the stdin JSON carries no separate field for it.
#
# No profile (.milestone-config/driver.json, legacy root milestone-driver.json)
# -> silent. No .milestone-config/.runtime/wave-state.json -> silent.
# Unparsable JSON (stdin or the state file) -> silent. Escape:
# CLAUDE_HOOK_DISABLE_SESSION_RESUME=1. Exit 0 always - this hook only prints
# context, it never gates. bash-3.2-safe (macOS /bin/bash smoke venue): no
# mapfile, no associative arrays; a herestring feeds the row loop in the
# current shell so its accumulator variables survive it.

[ "${CLAUDE_HOOK_DISABLE_SESSION_RESUME:-}" = "1" ] && exit 0

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"

profile="$project_dir/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$project_dir/milestone-driver.json"
[ -f "$profile" ] || exit 0

state="$project_dir/.milestone-config/.runtime/wave-state.json"
[ -f "$state" ] || exit 0

rows="$(jq -r '
  to_entries
  | sort_by(.value.issue)
  | .[]
  | [ (.value.issue|tostring), (.value.wave|tostring), (.value.status // "-"),
      (.value.branch // "-"), (.value.pr // "-") ]
  | @tsv
' "$state" 2>/dev/null)"
[ -z "$rows" ] && exit 0

cap=40
count=0
more=0
table=''
while IFS=$'\t' read -r n w s b p; do
  [ -z "$n" ] && continue
  count=$((count + 1))
  if [ "$count" -le "$cap" ]; then
    table="${table}| ${n} | ${w} | ${s} | ${b} | ${p} |
"
  else
    more=$((more + 1))
  fi
done <<< "$rows"

printf '%s\n' '▶ milestone-driver: context was compacted during a milestone run. Resume from the checkpoint.'
printf '\n'
printf '%s\n' '| Issue | Wave | Status | Branch | PR |'
printf '%s\n' '|---|---|---|---|---|'
printf '%s' "$table"
[ "$more" -gt 0 ] && printf '… %s more\n' "$more"
printf '\n'
printf '%s\n' 'skills/solve-milestone/parallel-waves.md (Wave-state checkpoint - consult before probing)'
exit 0
