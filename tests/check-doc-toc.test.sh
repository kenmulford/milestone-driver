#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for check-doc-toc.sh (issue #490).
# Each fixture is a repo-root under tests/fixtures/check-doc-toc/<case>/
# mirroring the governed files' real relative paths; the fixture files'
# CONTENT is throwaway filler apart from their LINE COUNT and the POSITION of
# their first level-2-or-higher heading, which is all this checker reads. The
# expected emitted output lives in tests/fixtures/check-doc-toc/_expected/
# <case>.txt. The .sh and .ps1 runners assert against the SAME golden files
# (cross-impl parity), mirroring tests/check-size-budgets.test.{sh,ps1}.
#
# The five cases cover the four states issue #490 requires, plus the fenced
# caveat:
#   compliant             every row OK, exit 0. Its base tree carries, in ONE
#                         tree, every shape the scan has to get right: a file
#                         over the threshold with frontmatter and intro prose
#                         ahead of `## Contents` (skills/setup/SKILL.md, 120
#                         lines); one with an H1 ahead of it (solve-issue/
#                         SKILL.md, 101 - one line over); one with NO `^# `
#                         line anywhere, the real agents/*.md shape (agents/
#                         design-reviewer.md, 110); one whose H1-shaped bash
#                         comments sit inside a fence BEFORE `## Contents`
#                         (agents/implementer.md, 105); a file EXACTLY at the
#                         100-line threshold carrying no `## Contents` at all
#                         (solve-issue/async-mode.md); and a short file whose
#                         first heading is `## Overview` (md-epic-fanout.md,
#                         40). The last two are the "at or under the threshold
#                         passes regardless" half of the contract, and the
#                         async-mode.md one pins the boundary: 100 passes, 101
#                         is measured.
#   fenced-pseudo-heading same stream, exit 0, with solve-milestone/SKILL.md
#                         rewritten to carry a ```markdown fence holding
#                         `## v<target-version> - <milestone theme>` AFTER its
#                         `## Contents`. That is the real file's shape (its
#                         `## Contents` is line 18, the fenced pseudo-heading
#                         line 459). The scan stops at the FIRST heading, so
#                         the fenced lines are ordinary content and never
#                         become the heading under test. A checker that
#                         instead required EVERY `##` line to be Contents, or
#                         that scanned to the last one, fails this case.
#                         DOCUMENTED LIMITATION, deliberately not tested as a
#                         pass: a fenced heading-shaped line placed BEFORE the
#                         real first heading WOULD be read as a heading. The
#                         scan skips only the leading YAML frontmatter fence
#                         and is otherwise line-oriented, exactly like
#                         scripts/read-doc-section.sh's ATX scan. Do not add
#                         general fence parsing to make that case pass.
#   missing-heading       skills/triage/SKILL.md over the threshold with no
#                         `## Contents` anywhere -> FAIL that row, exit 1.
#   heading-not-first     the same file WITH `## Contents`, but behind a
#                         `## Overview` -> FAIL that row, exit 1. Present but
#                         late is not compliant, and this is the case a
#                         grep-for-the-string checker cannot tell from
#                         compliant.
#   missing-file          that path absent from disk -> FAIL <path> MISSING,
#                         exit 1 - never a silent pass.
#
# The last three trees are copies of the compliant tree with ONE file mutated
# or omitted, so every FAIL golden differs from compliant.txt in exactly one
# record. That is what keeps a regression readable: the diff names the file.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/check-doc-toc.sh"
FIX="tests/fixtures/check-doc-toc"
GOLD="$ROOT/$FIX/_expected"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

# case <name>|<wantExit>
declare -a CASES=(
  "compliant|0"
  "fenced-pseudo-heading|0"
  "missing-heading|1"
  "heading-not-first|1"
  "missing-file|1"
)

pass=0; fail=0
# Paths are passed RELATIVE to the repo root (and we cd there) so any path
# text in the output is checkout-independent and matches the committed golden
# exactly. Mirrors tests/check-size-budgets.test.sh.
cd "$ROOT"
for spec in "${CASES[@]}"; do
  IFS='|' read -r name wantExit <<< "$spec"
  exp="$GOLD/$name.txt"
  [ -f "$exp" ] || { echo "FAIL $name: missing golden $exp" >&2; fail=$((fail+1)); continue; }
  got="$(bash "$SCRIPT" "$FIX/$name" 2>&1)"; rc=$?
  # CR-normalize the golden so a CRLF checkout (Windows core.autocrlf) still
  # compares clean - the script's own stdout is already LF. Mirrors the .ps1
  # runner. stderr is folded into stdout, so a case that starts emitting on
  # stderr fails here as well as on the pwsh twin.
  want="$(tr -d '\r' < "$exp")"
  if [ "$got" = "$want" ] && [ "$rc" -eq "$wantExit" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: rc=$rc (want $wantExit)" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2 || true
  fi
done

echo "check-doc-toc.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
