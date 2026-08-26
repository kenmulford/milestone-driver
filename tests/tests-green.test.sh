#!/usr/bin/env bash
# milestone-driver - runner for the tests-green.sh hook (issue #499).
# The hook takes no arguments and emits no stdout record, so there is no case
# table to drive: every assertion here is bespoke, against a fresh mktemp
# workspace, exactly like the `write` blocks below the loop in
# tests/triage-cache.test.sh (The `write` subcommand MUTATES its root).
#
# What it pins: the .gitignore SELF-HEAL block, which the hook emits after a
# green suite. The block is a fifth declaring copy of the entry set whose
# authority is this repo's committed .milestone-config/.gitignore, and this
# runner is what keeps it from drifting the way it did before #499.
#
# Twin parity is asserted on the EMITTED bytes, never on the two hooks' source
# bytes: the .sh and .ps1 twins legitimately differ in source through quote
# escaping (milestone-feeder #207). Both legs of this runner compare their own
# twin's output against the SAME committed file, so agreement with the
# authority is what makes them agree with each other.
#
# bash-3.2-safe (macOS ships 3.2 and never bash 4+): no `local -n`, no
# mapfile/readarray, no `${var,,}`.
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
# Hook child interpreter, resolved once. The hooks ship for whatever bash the
# consumer has, and on macOS that is /bin/bash 3.2 - a live venue this runner
# must keep covering. PATH bash is NOT that venue on the macOS CI job:
# .github/workflows/ci.yml (Put a modern bash on PATH for runner children)
# deliberately puts a modern bash ahead of it for the runners' script children
# (#557), which masked the 3.2 hook child here. So on Darwin the hook child is
# named outright; elsewhere PATH bash is the venue.
BASH_BIN="$(command -v bash)"
if [ "$(uname -s)" = "Darwin" ] && [ -x /bin/bash ]; then BASH_BIN=/bin/bash; fi

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/tg.$$")"; mkdir -p "$TMP"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
ERRFILE="$TMP/err"

ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

# ws - a workspace staged so the hook reaches its post-green write. Every
# ingredient is load-bearing: a driver.json with a unitTestCmd (absent → exit
# 0), a staged path matching sourceGlobs (no match → exit 0), and a real git
# repo (`git write-tree` failing leaves the stamp key empty, which gates the
# whole self-heal block). `git --version` is the unitTestCmd on BOTH legs: it
# is a native command, so it exits 0 under `eval` here and sets $LASTEXITCODE
# to 0 under the pwsh twin's Invoke-Expression.
ws() {
  local w
  w="$(mktemp -d "$TMP/ws.XXXXXX")"
  git -C "$w" init -q
  git -C "$w" config user.email tests-green@example.invalid
  git -C "$w" config user.name tests-green
  mkdir -p "$w/.milestone-config" "$w/src"
  printf '%s\n' '{"unitTestCmd":"git --version","sourceGlobs":["src/**"]}' \
    > "$w/.milestone-config/driver.json"
  printf 'x\n' > "$w/src/a.txt"
  git -C "$w" add src/a.txt
  printf '%s' "$w"
}

# run_hook <root> - feed the hook the PreToolUse payload a `git commit` carries
# and capture its exit code. The hook writes only to stderr, so both streams go
# to one file; the assertions read the tree it left, not its chatter.
run_hook() {
  jq -n --arg cwd "$1" '{tool_input:{command:"git commit -m x"}, cwd:$cwd}' \
    | "$BASH_BIN" "$HOOK" > "$ERRFILE" 2>&1
  RC=$?
  ERR="$(cat "$ERRFILE")"
}

# ---- self-healed .gitignore is byte-identical to the committed one ----------
# The block lives in the hook, so this is what keeps it in sync with
# .milestone-config/.gitignore in this repo.
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
# The self-heal is create-only at every site, so a user-edited file must survive
# untouched - not overwritten, not appended to, not truncated. Precedent:
# tests/triage-cache.test.sh (write: an EXISTING .gitignore is never rewritten).
W="$(ws)"
printf 'sentinel\n' > "$W/.milestone-config/.gitignore"
run_hook "$W"
KEPT="$(cat "$W/.milestone-config/.gitignore" 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ "$KEPT" = "sentinel" ]; then ok; else
  no "gitignore-preserved: rc=$RC content=[$KEPT] err=[$ERR]"; fi

echo "tests-green.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
