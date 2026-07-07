#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for check-skill-frontmatter.sh (issue #314).
# Each fixture is a repo-root under tests/fixtures/check-skill-frontmatter/<case>/
# mirroring the governed SKILL.md files' real relative paths; the fixture files'
# BODY is throwaway filler — only their FRONTMATTER is asserted. The expected
# emitted output lives in tests/fixtures/check-skill-frontmatter/_expected/<case>.txt.
# The .sh and .ps1 runners assert against the SAME golden files (cross-impl
# parity), mirroring tests/check-size-budgets.test.{sh,ps1}.
#
# Cases prove the defect-class semantics required by issue #314:
#   clean          — a folded `>-` description carrying `parallel: false` PASSES
#                    (block scalars are safe; this is the exact #314 fix shape).
#   defect         — an unquoted plain `description:` carrying `parallel: false`
#                    FAILS, naming the file + key (the exact reintroduced defect).
#   missing-file   — an absent governed SKILL.md FAILS as MISSING (never silent).
#   no-frontmatter — a SKILL.md with no opening `---` fence FAILS as NO-FRONTMATTER.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/check-skill-frontmatter.sh"
FIX="tests/fixtures/check-skill-frontmatter"
GOLD="$ROOT/$FIX/_expected"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

# case <name>|<wantExit>
declare -a CASES=(
  "clean|0"
  "defect|1"
  "missing-file|1"
  "no-frontmatter|1"
)

pass=0; fail=0
# Paths are passed RELATIVE to the repo root (and we cd there) so any path text
# in the output is checkout-independent and matches the committed golden
# exactly. Mirrors tests/check-size-budgets.test.sh.
cd "$ROOT"
for spec in "${CASES[@]}"; do
  IFS='|' read -r name wantExit <<< "$spec"
  exp="$GOLD/$name.txt"
  [ -f "$exp" ] || { echo "FAIL $name: missing golden $exp" >&2; fail=$((fail+1)); continue; }
  got="$(bash "$SCRIPT" "$FIX/$name" 2>&1)"; rc=$?
  # CR-normalize the golden so a CRLF checkout (Windows core.autocrlf) still
  # compares clean — the script's own stdout is already LF. Mirrors the .ps1 runner.
  want="$(tr -d '\r' < "$exp")"
  if [ "$got" = "$want" ] && [ "$rc" -eq "$wantExit" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: rc=$rc (want $wantExit)" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2 || true
  fi
done
echo "check-skill-frontmatter.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
