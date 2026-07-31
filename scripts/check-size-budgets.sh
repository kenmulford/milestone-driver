#!/usr/bin/env bash
# milestone-driver — CI size-budget ratchet (issue #295).
# Byte ceiling added by issue #399.
#
# Guards the size of a small set of GOVERNED files (the core skills/*/SKILL.md
# files, the reviewer/implementer agents/*.md files, and the sibling reference
# docs split out of the once-monolithic SKILL.md files) against TWO per-file
# ceilings recorded in the table below: a LINE ceiling and a BYTE ceiling.
# Dependency-free: `wc -l` and `wc -c` only, no YAML/markdown library (mirrors
# ci-preflight-steps.sh's line-oriented-parser posture;
# .project/library-manifest.md#Adding a dependency (the gate), "no new tool
# dependency").
#
# Which unit is authoritative (issue #399):
#   - BYTES is authoritative for COST. Every governed file loads into context
#     on every run, and that cost tracks bytes, not lines. So prose APPENDED TO
#     AN EXISTING LINE IS governed here: it moves the byte count while the
#     line count does not move at all. PR #398 appended 1052 bytes to
#     skills/solve-milestone/SKILL.md at a flat 664 lines and this ratchet
#     reported no change; three later merges added another 3818 bytes ACROSS
#     THE GOVERNED SET the same way (#363 +1200, #365 +2439, #397 +179, all
#     at zero line delta, none of them in that file). The byte ceiling sees it.
#   - LINES is kept as a second, independent ceiling, not replaced: this repo's
#     cross-file `file:line` citations anchor to line numbers, so line growth
#     carries a cost of its own that a byte count cannot express (issue #397
#     re-derived 18 citations staled by line shifts).
#   - BYTES, NOT CHARACTERS. This script runs under LC_ALL=C, where `wc -m`
#     already returns bytes; and a character count cannot be made
#     byte-identical across the bash/pwsh twins, because .NET strings are
#     UTF-16 (an astral character, which includes most emoji, is 1 character to
#     a UTF-8-aware count but 2 code units to a naive .Length). Bytes are
#     locale-independent and identical on both sides by construction.
#   - BYTES, NOT WORDS, even though superpowers:writing-skills (a domainSkill
#     of this repo) sizes skills with `wc -w`. Word count splits on whitespace,
#     so "scripts/check-size-budgets.ps1" scores 1 word for 30 bytes; these
#     files are dense with such path/flag/backtick tokens, which is the content
#     shape word count undercounts worst.
#   - Byte counts read the file ON DISK. A CRLF working tree (Windows
#     core.autocrlf) therefore reads one extra byte per line, at most ~2% of
#     any file governed here, which the headroom below absorbs. The LINE count
#     stays CRLF-proof (the pwsh twin counts 0x0A bytes).
#
# Ceiling discipline (documented, not machine-enforced):
#   - CEILINGS ONLY GO DOWN, NEVER UP. Each ceiling starts at the governed
#     file's actual count (when the ratchet was introduced, or last tightened)
#     plus ~5% headroom. A LINE ceiling rounds to a clean number; a BYTE
#     ceiling ROUNDS UP TO THE NEXT 500 BYTES, a fixed granularity so that at
#     byte scale the 14 derivations stay arithmetic instead of 14 judgment
#     calls.
#   - When a governed file SHRINKS (a future split/trim), lower BOTH its
#     ceilings to the new actuals + headroom in the SAME change that shrinks it.
#   - Raising a ceiling requires a recorded decision in the Decision Log of
#     the PR body that grows the file. This script enforces whatever ceiling
#     it is given — it has no opinion on when raising one is warranted.
#   - A governed file that is renamed or deleted is a FAILURE, not a silent
#     pass — the table must be updated (moved or removed) in the SAME change,
#     with a recorded decision if a file is dropped from governance.
#
# Usage:   check-size-budgets.sh [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# Output (stdout), one line per governed file plus a trailing summary,
# TAB-separated (mirrors ci-preflight-steps.sh's STEP/SKIP/SUMMARY stream):
#   OK    <path>  <lines>/<lineCeiling>  <bytes>/<byteCeiling>
#   FAIL  <path>  <lines>/<lineCeiling>  <bytes>/<byteCeiling>
#   FAIL  <path>  MISSING/<lineCeiling>  MISSING/<byteCeiling>
#   SUMMARY ok=<N> failed=<M>
# A file FAILS when EITHER count is over its ceiling, and both columns always
# print, so the record itself shows which one moved. Exit 0 when every governed
# file is present and at/under BOTH ceilings; exit 1 when any file is missing
# or over. bash-3.2-safe (no ${var,,}, no `declare -A`, no `mapfile`).
set -u
export LC_ALL=C

ROOT="${1:-$PWD}"
ROOT="${ROOT%/}"

# Parallel arrays (bash-3.2-safe — no associative arrays). Index i in FILES
# lines up with CEILINGS[i] (lines) and BYTE_CEILINGS[i] (bytes). See the
# header for the ratchet discipline that governs these numbers.
FILES=(
  "skills/setup/SKILL.md"
  "skills/solve-issue/SKILL.md"
  "skills/solve-issue/async-mode.md"
  "skills/solve-issue/md-epic-fanout.md"
  "skills/solve-milestone/SKILL.md"
  "skills/solve-milestone/parallel-waves.md"
  "skills/solve-milestone/trello-sync.md"
  "skills/solve-milestone/milestone-granularity.md"
  "skills/triage/SKILL.md"
  "skills/notices.md"
  "skills/output-style.md"
  "agents/design-reviewer.md"
  "agents/implementer.md"
  "agents/triage-reviewer.md"
)
CEILINGS=(
  280
  400
  40
  60
  680
  215
  400
  165
  460
  250
  100
  115
  130
  120
)
# BYTE ceilings, set from the actuals measured at introduction (issue #399) as
# actual * 1.05 rounded UP to the next 500 bytes. Same ratchet discipline as
# CEILINGS above: down freely, up only with a decision recorded in the PR body.
BYTE_CEILINGS=(
  33500
  78000
  5000
  9500
  80500
  68000
  21500
  25500
  42000
  13500
  10500
  16500
  15000
  16500
)

# Length-parity guard: the three tables are hand-edited parallel arrays with no
# structural link between them — a dropped/added line in one and not the
# others must fail loud, not desync the loop (which would misattribute
# ceilings under `set -u`, or die mid-loop on an unbound index).
if [ "${#FILES[@]}" -ne "${#CEILINGS[@]}" ] || [ "${#FILES[@]}" -ne "${#BYTE_CEILINGS[@]}" ]; then
  printf 'ERROR check-size-budgets: FILES(%s), CEILINGS(%s) and BYTE_CEILINGS(%s) length mismatch, fix the table\n' \
    "${#FILES[@]}" "${#CEILINGS[@]}" "${#BYTE_CEILINGS[@]}" >&2
  exit 1
fi

ok=0
failed=0
i=0
while [ "$i" -lt "${#FILES[@]}" ]; do
  f="${FILES[$i]}"
  ceiling="${CEILINGS[$i]}"
  byte_ceiling="${BYTE_CEILINGS[$i]}"
  path="$ROOT/$f"
  if [ ! -f "$path" ]; then
    printf 'FAIL\t%s\tMISSING/%s\tMISSING/%s\n' "$f" "$ceiling" "$byte_ceiling"
    failed=$((failed + 1))
  else
    actual="$(wc -l < "$path")"
    actual="${actual//[[:space:]]/}"
    # `wc -c` is bytes on disk on every platform (BSD and GNU alike) and needs
    # no locale, matching the pwsh twin's $bytes.Length on the same file.
    actual_bytes="$(wc -c < "$path")"
    actual_bytes="${actual_bytes//[[:space:]]/}"
    if [ "$actual" -gt "$ceiling" ] || [ "$actual_bytes" -gt "$byte_ceiling" ]; then
      printf 'FAIL\t%s\t%s/%s\t%s/%s\n' "$f" "$actual" "$ceiling" "$actual_bytes" "$byte_ceiling"
      failed=$((failed + 1))
    else
      printf 'OK\t%s\t%s/%s\t%s/%s\n' "$f" "$actual" "$ceiling" "$actual_bytes" "$byte_ceiling"
      ok=$((ok + 1))
    fi
  fi
  i=$((i + 1))
done

printf 'SUMMARY\tok=%s\tfailed=%s\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
