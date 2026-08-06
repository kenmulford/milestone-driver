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
#     core.autocrlf) therefore reads one extra byte per line: 0.29% to 2.27%
#     across the governed set. THE HEADROOM DOES NOT ABSORB THAT, and an earlier
#     version of this comment claiming it did was wrong. Measured on a simulated
#     autocrlf tree, TODAY: agents/design-reviewer.md carries 0.55% headroom
#     against a 0.72% CRLF cost, so it STILL FAILS (16528/16500) on a Windows
#     contributor's first clone, on a file they never touched. Its twin
#     agents/triage-reviewer.md no longer does: issue #464 raised that file's
#     byte ceiling for reasons unrelated to CRLF, and 16689/17000 now absorbs
#     the cost. That is one file clearing it, not the set, and the pin is what
#     keeps it from mattering. What guarantees the byte ceilings mean the
#     same number on every platform is the `*.md text eol=lf` PIN in
#     .gitattributes, alongside the pins already held by *.sh, *.ps1, *.tsv,
#     *.txt, *.yml and tests/fixtures/**. Do not remove it, and do not size a
#     ceiling to tolerate CRLF instead. The LINE count stays CRLF-proof either
#     way (the pwsh twin counts 0x0A bytes).
#
# Ceiling discipline (documented, not machine-enforced):
#   - CEILINGS ONLY GO DOWN, NEVER UP. Each ceiling starts at the governed
#     file's actual count (when the ratchet was introduced, or last tightened)
#     plus ~5% headroom, ROUNDED UP TO A FIXED GRANULARITY so the 15 derivations
#     stay arithmetic instead of 15 judgment calls: the next 500 BYTES on the
#     byte axis, the next 5 LINES on the line axis.
#   - BOTH AXES CARRY A MINIMUM-HEADROOM FLOOR, and the line axis needs its own
#     because 5% of a small line count is not a usable allowance. A LINE CEILING
#     IS NEVER LOWERED BELOW `actual + 5` ROUNDED UP TO THE NEXT 5. Without it,
#     5% of a 33-line file granted 2 lines: skills/solve-issue/async-mode.md
#     derived a 35-line ceiling that an ordinary 3-line bullet would break while
#     the file still sat 473 bytes under its byte ceiling, and
#     md-epic-fanout.md at 52 lines was the same shape. The 500-byte granularity
#     already does this job on the byte axis, which is why only the line axis
#     had to be told. APPLY BOTH AXES' FLOORS on every re-derivation.
#   - When a governed file SHRINKS (a future split/trim), lower BOTH its
#     ceilings to the new actuals + headroom in the SAME change that shrinks it.
#   - Raising a ceiling requires a recorded decision in the Decision Log of
#     the PR body that grows the file. This script enforces whatever ceiling
#     it is given — it has no opinion on when raising one is warranted.
#     RECORDED RAISE, issue #464 (decision 2026-08-06): agents/triage-reviewer.md
#     BYTE 16500 -> 17000, agents/design-reviewer.md LINE 115 -> 120, each
#     narrowed to what its own file actually needed rather than raised in
#     lockstep. That authorization is spent on that issue's three fixes and
#     covers nothing else: the next edit to either row re-derives normally, and
#     both go down again from there.
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

# The governed set, ONE ROW PER FILE:
#
#   <path>   <lineCeiling>   <byteCeiling>
#
# All three columns of a file sit on the same line, so a file's two ceilings
# can no longer be MOVED apart from their path, and every number is read next
# to the path it belongs to. Issue #428 is why: this used to be three
# free-standing parallel arrays, and length was all the guard below compared.
# Swapping two entries inside FILES alone kept all three lengths equal, passed
# the guard, measured each file against the other's ceiling and still exited 0
# — and reading a ceiling meant counting down an unlabelled column, which on
# 2026-08-05 mis-reported skills/triage/SKILL.md as having 26KB of byte
# headroom when it had 66 bytes. One row per file removes that MOVE, and every
# plausible accident with it; deliberately swapping two path STRINGS between
# rows still desyncs silently, which no table shape can prevent. See the header
# for the ratchet discipline that governs these numbers. Rows start at column
# 0; `#` starts a comment row.
#
# BYTE ceilings were set from the actuals measured at introduction (issue #399)
# as actual * 1.05 rounded UP to the next 500 bytes. Same ratchet discipline as
# the line ceilings: down freely, up only with a decision recorded in the PR
# body.
FILES=()
CEILINGS=()
BYTE_CEILINGS=()
nfiles=0
nceilings=0
nbytes=0
# A row contributes to a ceiling array only when that column is present AND all
# digits, so a hand-edit that drops or garbles a column leaves the three counts
# unequal and trips the parity guard below. Without the digit check a garbled
# ceiling would reach `[ "$actual" -gt "$ceiling" ]`, which prints "integer
# expression expected" on stderr and then takes the FALSE branch — a silent OK,
# the same shape of quiet wrong answer #428 removed.
# bash-3.2-safe: `read` and `case` builtins plus index assignment, no
# associative arrays and no `mapfile`; the heredoc feeds the loop in the
# CURRENT shell, so the arrays it fills survive it.
while read -r f line_ceiling byte_ceiling; do
  case "$f" in ''|'#'*) continue ;; esac
  FILES[$nfiles]="$f"; nfiles=$((nfiles + 1))
  case "$line_ceiling" in ''|*[!0-9]*) ;; *) CEILINGS[$nceilings]="$line_ceiling"; nceilings=$((nceilings + 1)) ;; esac
  case "$byte_ceiling" in ''|*[!0-9]*) ;; *) BYTE_CEILINGS[$nbytes]="$byte_ceiling"; nbytes=$((nbytes + 1)) ;; esac
done <<'GOVERNED_TABLE'
skills/setup/SKILL.md                             280    30000
skills/solve-issue/SKILL.md                       375    69500
skills/solve-issue/async-mode.md                   40     4500
skills/solve-issue/md-epic-fanout.md               60     9000
skills/solve-milestone/SKILL.md                   635    69000
skills/solve-milestone/parallel-waves.md          205    68000
skills/solve-milestone/trello-sync.md             400    20500
skills/solve-milestone/milestone-granularity.md   165    25000
skills/triage/SKILL.md                            390    37000
skills/notices.md                                 250    11500
skills/output-style.md                             90     9500
skills/citation-format.md                         230    13000
agents/design-reviewer.md                         120    16500
agents/implementer.md                             130    15000
agents/triage-reviewer.md                         120    17000
GOVERNED_TABLE

# Length-parity guard: the parse above appends a path unconditionally and each
# ceiling only when its column is present and numeric, so a malformed row shows
# up here as unequal counts. That must fail loud, not desync the loop (which
# would misattribute ceilings under `set -u`, or die mid-loop on an unbound
# index).
if [ "$nfiles" -ne "$nceilings" ] || [ "$nfiles" -ne "$nbytes" ]; then
  printf 'ERROR check-size-budgets: FILES(%s), CEILINGS(%s) and BYTE_CEILINGS(%s) length mismatch, fix the table\n' \
    "$nfiles" "$nceilings" "$nbytes" >&2
  exit 1
fi

ok=0
failed=0
i=0
while [ "$i" -lt "$nfiles" ]; do
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
