#!/usr/bin/env bash
# milestone-driver — CI size-budget ratchet (issue #295).
#
# Guards the line count of a small set of GOVERNED files — the core
# skills/*/SKILL.md files, the reviewer/implementer agents/*.md files, and the
# sibling reference docs split out of the once-monolithic SKILL.md files —
# against a per-file CEILING recorded in the table below. Dependency-free:
# `wc -l` only, no YAML/markdown library (mirrors ci-preflight-steps.sh's
# line-oriented-parser posture; .project/library-manifest.md#Adding a
# dependency (the gate) — "no new tool dependency").
#
# Ceiling discipline (documented, not machine-enforced):
#   - CEILINGS ONLY GO DOWN, NEVER UP. A ceiling starts at the governed file's
#     actual line count (when the ratchet was introduced, or last tightened)
#     plus ~5% headroom, rounded to a clean number.
#   - When a governed file SHRINKS (a future split/trim), lower its ceiling to
#     the new actual + headroom in the SAME change that shrinks it.
#   - Raising a ceiling requires a recorded decision on the issue that grows
#     the file. This script enforces whatever ceiling it is given — it has no
#     opinion on when raising one is warranted.
#   - A governed file that is renamed or deleted is a FAILURE, not a silent
#     pass — the table must be updated (moved or removed) in the SAME change,
#     with a recorded decision if a file is dropped from governance.
#
# Usage:   check-size-budgets.sh [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# Output (stdout), one line per governed file plus a trailing summary,
# TAB-separated (mirrors ci-preflight-steps.sh's STEP/SKIP/SUMMARY stream):
#   OK    <path>  <actual>/<ceiling>
#   FAIL  <path>  <actual-or-MISSING>/<ceiling>
#   SUMMARY ok=<N> failed=<M>
# Exit 0 when every governed file is present and at/under its ceiling; exit 1
# when any file is missing or over. bash-3.2-safe (no ${var,,}, no
# `declare -A`, no `mapfile`).
set -u
export LC_ALL=C

ROOT="${1:-$PWD}"
ROOT="${ROOT%/}"

# Parallel arrays (bash-3.2-safe — no associative arrays). Index i in FILES
# lines up with CEILINGS[i]. See the header for the ratchet discipline that
# governs these numbers.
FILES=(
  "skills/setup/SKILL.md"
  "skills/solve-issue/SKILL.md"
  "skills/solve-issue/worker-mode.md"
  "skills/solve-issue/async-mode.md"
  "skills/solve-issue/md-epic-fanout.md"
  "skills/solve-milestone/SKILL.md"
  "skills/solve-milestone/parallel-waves.md"
  "skills/solve-milestone/trello-sync.md"
  "skills/triage/SKILL.md"
  "skills/notices.md"
  "agents/design-reviewer.md"
  "agents/implementer.md"
  "agents/triage-reviewer.md"
)
CEILINGS=(
  280
  380
  70
  40
  60
  680
  200
  400
  460
  200
  115
  130
  120
)

# Length-parity guard: FILES/CEILINGS are hand-edited parallel arrays with no
# structural link between them — a dropped/added line in one and not the
# other must fail loud, not desync the loop (which would misattribute
# ceilings under `set -u`, or die mid-loop on an unbound index).
if [ "${#FILES[@]}" -ne "${#CEILINGS[@]}" ]; then
  printf 'ERROR check-size-budgets: FILES(%s) and CEILINGS(%s) length mismatch — fix the table\n' \
    "${#FILES[@]}" "${#CEILINGS[@]}" >&2
  exit 1
fi

ok=0
failed=0
i=0
while [ "$i" -lt "${#FILES[@]}" ]; do
  f="${FILES[$i]}"
  ceiling="${CEILINGS[$i]}"
  path="$ROOT/$f"
  if [ ! -f "$path" ]; then
    printf 'FAIL\t%s\tMISSING/%s\n' "$f" "$ceiling"
    failed=$((failed + 1))
  else
    actual="$(wc -l < "$path")"
    actual="${actual//[[:space:]]/}"
    if [ "$actual" -gt "$ceiling" ]; then
      printf 'FAIL\t%s\t%s/%s\n' "$f" "$actual" "$ceiling"
      failed=$((failed + 1))
    else
      printf 'OK\t%s\t%s/%s\n' "$f" "$actual" "$ceiling"
      ok=$((ok + 1))
    fi
  fi
  i=$((i + 1))
done

printf 'SUMMARY\tok=%s\tfailed=%s\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
