#!/usr/bin/env bash
# milestone-driver — behavior matrix runner for read-doc-section.sh (issue #184).
# Each case builds a tiny Markdown fixture in a per-run temp dir and asserts the
# stdout, the exit code, AND (on failure cases) that stdout is empty + stderr
# names the anchor/file. The .sh and .ps1 runners assert the SAME contract
# (cross-impl parity), mirroring tests/extract-version.test.{sh,ps1}.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/read-doc-section.sh"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

pass=0; fail=0
# Per-run temp dir for fixtures + captured stderr — mktemp -d avoids fixed-path
# collisions under concurrent runs and is portable; trap removes it on exit.
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/rds.$$")"; mkdir -p "$TMP"
trap 'rm -f "$ERRFILE"; rm -rf "$TMP"' EXIT
ERRFILE="$TMP/err"

# A representative fixture: nested levels, a duplicate anchor, and a last section
# (for the EOF case). Heading-match is on the text AFTER the leading #s, trimmed.
DOC="$TMP/sample.md"
cat > "$DOC" <<'EOF'
# Title

Intro prose.

## Keys

Keys body line 1.

### Sub

Nested deeper than ## — stays inside Keys.

## Other

Other body.

## Keys

Duplicate Keys — must NOT be reached (first-match policy).

## Last

Last body, runs to EOF.
EOF

# check <name> <expectExit> <expectStdout-or-__SKIP__> <args...>
# When expectStdout is __SKIP__ we only assert exit + empty stdout + nonempty stderr.
check() {
  local name="$1" wantExit="$2" wantOut="$3"; shift 3
  local out rc err
  out="$(bash "$SCRIPT" "$@" 2>"$ERRFILE")"; rc=$?
  err="$(cat "$ERRFILE")"
  if [ "$wantOut" = "__FAIL__" ]; then
    # failure contract: nonzero exit, EMPTY stdout, NONEMPTY stderr
    if [ "$rc" -ne 0 ] && [ -z "$out" ] && [ -n "$err" ]; then
      pass=$((pass+1))
    else
      fail=$((fail+1))
      printf 'FAIL %-18s rc=%s out=[%s] err=[%s] (want nonzero rc, empty out, nonempty err)\n' \
        "$name" "$rc" "$out" "$err" >&2
    fi
  else
    if [ "$rc" -eq "$wantExit" ] && [ "$out" = "$wantOut" ]; then
      pass=$((pass+1))
    else
      fail=$((fail+1))
      printf 'FAIL %-18s rc=%s(want %s)\n--- got stdout ---\n%s\n--- want stdout ---\n%s\n--- stderr ---\n%s\n' \
        "$name" "$rc" "$wantExit" "$out" "$wantOut" "$err" >&2
    fi
  fi
}

# 1) Happy path: ## Keys -> heading line through line before next <= level heading.
#    The ### Sub subsection is deeper, so it stays inside; stops before ## Other.
read -r -d '' WANT_KEYS <<'EOF' || true
## Keys

Keys body line 1.

### Sub

Nested deeper than ## — stays inside Keys.
EOF
check happy 0 "$WANT_KEYS" "$DOC" "Keys"

# 2) EOF case: ## Last is the final section -> runs to end of file.
read -r -d '' WANT_LAST <<'EOF' || true
## Last

Last body, runs to EOF.
EOF
check eof 0 "$WANT_LAST" "$DOC" "Last"

# 3) Missing/renamed anchor -> nonzero exit, empty stdout, stderr names it.
check missing-anchor 1 __FAIL__ "$DOC" "DoesNotExist"

# 4) Missing file -> nonzero exit, empty stdout, stderr names it.
check missing-file 1 __FAIL__ "$TMP/nope.md" "Keys"

# 5) Bad usage (wrong arg count) -> nonzero exit, stderr usage.
check usage 2 __FAIL__ "$DOC"

echo "read-doc-section.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
