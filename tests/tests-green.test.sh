#!/usr/bin/env bash
# milestone-driver - runner for the tests-green.sh hook (issue #499).
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
HOOK="$ROOT/hooks/tests-green.sh"
REPO_GITIGNORE="$ROOT/.milestone-config/.gitignore"
[ -f "$HOOK" ] || { echo "FATAL: missing $HOOK" >&2; exit 3; }
[ -f "$REPO_GITIGNORE" ] || { echo "FATAL: missing $REPO_GITIGNORE" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 3; }
BASH_BIN="$(command -v bash)"
if [ "$(uname -s)" = "Darwin" ] && [ -x /bin/bash ]; then BASH_BIN=/bin/bash; fi

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/tg.$$")"; mkdir -p "$TMP"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
ERRFILE="$TMP/err"

ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

ws() {
  local w globs f
  globs="${1:-[\"src/**\"]}"
  f="${2:-src/a.txt}"
  w="$(mktemp -d "$TMP/ws.XXXXXX")"
  git -C "$w" init -q
  git -C "$w" config user.email tests-green@example.invalid
  git -C "$w" config user.name tests-green
  mkdir -p "$w/.milestone-config" "$w/$(dirname "$f")"
  printf '{"unitTestCmd":"git --version","sourceGlobs":%s}\n' "$globs" \
    > "$w/.milestone-config/driver.json"
  printf 'x\n' > "$w/$f"
  git -C "$w" add "$f"
  printf '%s' "$w"
}

run_hook() {
  jq -n --arg cwd "$1" '{tool_input:{command:"git commit -m x"}, cwd:$cwd}' \
    | "$BASH_BIN" "$HOOK" > "$ERRFILE" 2>&1
  RC=$?
  ERR="$(cat "$ERRFILE")"
}

# ---- self-healed .gitignore is byte-identical to the committed one ----------
W="$(ws)"
run_hook "$W"
EMITTED="$W/.milestone-config/.gitignore"
if [ "$RC" -ne 0 ]; then
  no "gitignore-emitted: hook rc=$RC err=[$ERR]"
elif [ ! -f "$EMITTED" ]; then
  no "gitignore-emitted: hook wrote no $EMITTED (err=[$ERR])"
elif cmp -s "$EMITTED" "$REPO_GITIGNORE"; then ok; else
  no "gitignore-emitted: differs from $REPO_GITIGNORE"
  diff "$REPO_GITIGNORE" "$EMITTED" >&2 || true; fi

# ---- an EXISTING .gitignore is never rewritten ------------------------------
W="$(ws)"
printf 'sentinel\n' > "$W/.milestone-config/.gitignore"
run_hook "$W"
KEPT="$(cat "$W/.milestone-config/.gitignore" 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ "$KEPT" = "sentinel" ]; then ok; else
  no "gitignore-preserved: rc=$RC content=[$KEPT] err=[$ERR]"; fi

# ---- a globstar-prefix glob does not match a root-level staged path --------
W="$(ws '["**/*.md"]' 'x.md')"
run_hook "$W"
if [ "$RC" -eq 0 ] && [ ! -f "$W/.milestone-config/.gitignore" ]; then ok; else
  no "globstar-root: rc=$RC (want 0) and the hook must not reach its post-green write, err=[$ERR]"; fi

echo "tests-green.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
