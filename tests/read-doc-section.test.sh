#!/usr/bin/env bash
# milestone-driver - behavior matrix runner for read-doc-section.sh (issue #184).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/read-doc-section.sh"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/rds.$$")"; mkdir -p "$TMP"
trap 'rm -f "$ERRFILE"; rm -rf "$TMP"' EXIT
ERRFILE="$TMP/err"

DOC="$TMP/sample.md"
cat > "$DOC" <<'EOF'
# Title

Intro prose.

## Keys

Keys body line 1.

### Sub

Nested deeper than ## - stays inside Keys.

## Other

Other body.

## Keys

Duplicate Keys - must NOT be reached (first-match policy).

## Last

Last body, runs to EOF.
EOF

check() {
  local name="$1" wantExit="$2" wantOut="$3"; shift 3
  local out rc err
  out="$(bash "$SCRIPT" "$@" 2>"$ERRFILE")"; rc=$?
  err="$(cat "$ERRFILE")"
  if [ "$wantOut" = "__FAIL__" ]; then
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

read -r -d '' WANT_KEYS <<'EOF' || true
## Keys

Keys body line 1.

### Sub

Nested deeper than ## - stays inside Keys.
EOF
check happy 0 "$WANT_KEYS" "$DOC" "Keys"

read -r -d '' WANT_LAST <<'EOF' || true
## Last

Last body, runs to EOF.
EOF
check eof 0 "$WANT_LAST" "$DOC" "Last"

check missing-anchor 1 __FAIL__ "$DOC" "DoesNotExist"

check missing-file 1 __FAIL__ "$TMP/nope.md" "Keys"

check usage 2 __FAIL__ "$DOC"

echo "read-doc-section.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
