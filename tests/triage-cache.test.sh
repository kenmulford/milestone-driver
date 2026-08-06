#!/usr/bin/env bash
# milestone-driver — golden-matrix runner for triage-cache.sh (issue #441).
# Each row of triage-cache.cases.tsv is: name<TAB>args<TAB>stdout_file<TAB>
# want_exit<TAB>stderr_file. See that table's header for what each column means
# and what each case proves. The runner cd's into tests/fixtures/triage-cache/
# and passes every path RELATIVE, so nothing the script echoes is
# checkout-dependent (mirrors tests/resolve-citation.test.sh's per-case cd). It
# asserts the exit code, stdout, AND stderr exactly.
#
# RAW vs NORMALIZED — same rule as tests/resolve-citation.test.sh (RAW vs NORMALIZED — the distinction):
#   * The ACTUAL stdout/stderr is captured RAW and compared byte-for-byte. It is
#     never CR-stripped and never rebuilt from a line array: either would make
#     the runner blind to CRLF creep and to a missing trailing newline, the
#     precise twin-parity bugs a golden matrix exists to catch.
#   * The GOLDEN gets ONE normalization, CRLF -> LF, because a CRLF working tree
#     (Windows core.autocrlf) rewrites the committed goldens.
# The .sh and .ps1 runners drive the SAME cases table against the SAME goldens
# (cross-impl parity).
#
# The `write` subcommand MUTATES its root, so it cannot be driven from a
# committed fixture. It is covered by the bespoke blocks below the loop, each
# against a fresh mktemp workspace, asserting the record on stdout AND the
# resulting tree. The cache FILE is asserted by PARSED CONTENT, not bytes: the
# two twins use different JSON serializers, and only stdout/stderr is byte-pinned
# (tests/write-cost-record.test.sh (assert the parsed NUMBER, never the bytes) makes the same call).
# The last bespoke block is bash-only: SKIP no-jq has no pwsh counterpart,
# because that twin parses JSON with built-in .NET types.
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/triage-cache.sh"
CASES="$HERE/triage-cache.cases.tsv"
FIX="$HERE/fixtures/triage-cache"
GOLD="$FIX/_expected"
SCRIPT_NAME="triage-cache.sh"
REPO_GITIGNORE="$ROOT/.milestone-config/.gitignore"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
[ -f "$CASES" ] || { echo "FATAL: missing $CASES" >&2; exit 3; }
[ -d "$FIX" ] || { echo "FATAL: missing $FIX" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
BASH_BIN="$(command -v bash)"

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/tc.$$")"; mkdir -p "$TMP"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
OUTFILE="$TMP/out"
ERRFILE="$TMP/err"

TAB=$'\t'
EXPECT_COLS=5
# split_tab <row> — bash-3.2-safe TAB split preserving empty fields ("IFS=$'\t'
# read" collapses adjacent tabs, silently dropping the empty stdout_file /
# stderr_file columns). NO mapfile/readarray (bash-4+ builtins; macOS ships 3.2).
# Sets the GLOBAL `cols` array directly. Copied from tests/resolve-citation.test.sh (bash-3.2-safe TAB split).
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}

# slurp_x <path> — a file's contents with a literal 'X' sentinel appended.
# Callers do out="$(slurp_x f)"; out="${out%X}" — the sentinel is what survives
# command substitution's trailing-newline stripping, so the capture stays RAW
# down to the final byte.
slurp_x() { cat "$1"; printf X; }

ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

case_count=0
while IFS= read -r row || [ -n "$row" ]; do
  # Strip the CRLF checkout's CR FIRST, so the blank/comment skip below sees the
  # same row text the .ps1 leg does.
  row="${row%$'\r'}"
  case "$row" in ''|\#*) continue;; esac
  split_tab "$row"
  # Self-guard: a row that doesn't parse into exactly the expected column count
  # is a runner bug (or a corrupt fixture), not a silently-defaulted pass.
  if [ "${#cols[@]}" -ne "$EXPECT_COLS" ]; then
    echo "FATAL: row failed to parse (got ${#cols[@]} fields, want $EXPECT_COLS): [$row]" >&2
    exit 1
  fi
  case_count=$((case_count+1))
  name="${cols[0]}"; args="${cols[1]}"; stdout_file="${cols[2]}"
  want_exit="${cols[3]}"; stderr_file="${cols[4]}"

  # Expected stdout: the named golden, CRLF->LF only (see RAW vs NORMALIZED).
  # A NAMED-BUT-MISSING golden is FATAL, never a silent "expect empty".
  if [ -n "$stdout_file" ]; then
    [ -f "$GOLD/$stdout_file" ] || { echo "FATAL: case $name names a missing golden: $GOLD/$stdout_file" >&2; exit 3; }
    exp_out="$(slurp_x "$GOLD/$stdout_file")"; exp_out="${exp_out%X}"
    exp_out="${exp_out//$'\r\n'/$'\n'}"
  else
    exp_out=""
  fi
  if [ -n "$stderr_file" ]; then
    [ -f "$GOLD/$stderr_file" ] || { echo "FATAL: case $name names a missing golden: $GOLD/$stderr_file" >&2; exit 3; }
    exp_err="$(slurp_x "$GOLD/$stderr_file")"; exp_err="${exp_err%X}"
    exp_err="${exp_err//$'\r\n'/$'\n'}"
    exp_err="${exp_err//__SCRIPT__/$SCRIPT_NAME}"
  else
    exp_err=""
  fi

  # `set -f` before the word split so a `*` or `?` in an args cell could never
  # glob against the fixture tree; the subshell keeps both the cd and the
  # positional-parameter rewrite from leaking between cases.
  (
    set -f
    set -- $args
    set +f
    cd "$FIX" && "$BASH_BIN" "$SCRIPT" "$@" >"$OUTFILE" 2>"$ERRFILE"
  ); rc=$?
  out="$(slurp_x "$OUTFILE")"; out="${out%X}"
  err="$(slurp_x "$ERRFILE")"; err="${err%X}"

  if [ "$rc" -eq "$want_exit" ] && [ "$out" = "$exp_out" ] && [ "$err" = "$exp_err" ]; then
    ok
  else
    no "$name: rc=$rc (want $want_exit)"
    # od -c so a CR / missing-newline mismatch is visible in the diff rather
    # than rendering identically to the expected text.
    diff <(printf '%s' "$exp_out" | od -c) <(printf '%s' "$out" | od -c) >&2 || true
    printf '  stderr got[%s] want[%s]\n' "$err" "$exp_err" >&2
  fi
done < "$CASES"

# Self-guard: zero parsed cases means every row was skipped or the table is
# empty — the suite would otherwise report "0 passed, 0 failed" as a clean,
# misleadingly-green exit.
if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES — this run tested nothing" >&2
  exit 1
fi

# Every assertion below the TSV loop is a bespoke case; the count is derived at
# the end (total assertions minus TSV rows) so a block added here can never
# report a stale total.
ws() { mktemp -d "$TMP/ws.XXXXXX"; }
run_write() { # <root> <entries> -> OUT/RC
  OUT="$("$BASH_BIN" "$SCRIPT" write "$1" "$2" 2>"$ERRFILE")"; RC=$?
  ERR="$(cat "$ERRFILE")"
}

# ---- write: merge onto an existing canonical cache --------------------------
# Entry 7 is overwritten, entry 11 is added, and entry 9 — which the input never
# mentions — must survive UNTOUCHED, triaged_at byte-for-byte included. That
# last part is the regression guard for a JSON round-trip that reformats values
# it does not own.
W="$(ws)"; cp -R "$FIX/roots/hit/." "$W/"
run_write "$W" "$FIX/entries-two.json"
CACHE="$W/.milestone-config/triage-cache.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "OK${TAB}.milestone-config/triage-cache.json" ] && [ -z "$ERR" ] \
   && jq -e '(keys | sort) == ["11","7","9"]
             and .["7"].key == "7:2026-08-02T00:00:00Z:4:alpha,zeta"
             and .["9"].key == "9:STALE-KEY"
             and .["9"].triaged_at == "2026-08-01T01:00:00Z"
             and .["9"].result.edges == [100]
             and .["11"].result.risk == "heavy"' "$CACHE" >/dev/null; then ok; else
  no "write-merge: rc=$RC out=[$OUT] err=[$ERR] cache=$(cat "$CACHE" 2>/dev/null)"; fi

# ---- write: self-healed .gitignore is byte-identical to the committed one ----
# The block lives in the script now, so this is what keeps it in sync with
# .milestone-config/.gitignore in this repo.
if [ ! -f "$REPO_GITIGNORE" ]; then
  no "write-gitignore: missing $REPO_GITIGNORE"
elif cmp -s "$W/.milestone-config/.gitignore" "$REPO_GITIGNORE"; then ok; else
  no "write-gitignore: differs from $REPO_GITIGNORE"
  diff "$REPO_GITIGNORE" "$W/.milestone-config/.gitignore" >&2 || true; fi

# ---- write: an EXISTING .gitignore is never rewritten ------------------------
W="$(ws)"; mkdir -p "$W/.milestone-config"; printf 'sentinel\n' > "$W/.milestone-config/.gitignore"
run_write "$W" "$FIX/entries-two.json"
if [ "$RC" -eq 0 ] && [ "$(cat "$W/.milestone-config/.gitignore")" = "sentinel" ]; then ok; else
  no "write-gitignore-preserved: rc=$RC content=[$(cat "$W/.milestone-config/.gitignore")]"; fi

# ---- write: legacy root cache is READ, then REMOVED --------------------------
W="$(ws)"; cp "$FIX/roots/legacy-only/.milestone-driver-triage-cache.json" "$W/"
run_write "$W" "$FIX/entries-two.json"
if [ "$RC" -eq 0 ] && [ ! -e "$W/.milestone-driver-triage-cache.json" ] \
   && jq -e '(keys | sort) == ["11","7","9"]' "$W/.milestone-config/triage-cache.json" >/dev/null; then ok; else
  no "write-legacy-cleanup: rc=$RC legacy_present=$([ -e "$W/.milestone-driver-triage-cache.json" ] && echo yes || echo no)"; fi

# ---- write: every failure path is exit 0 + one SKIP record -------------------
W="$(ws)"
run_write "$W" "$FIX/entries-bad.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "SKIP${TAB}bad-entries" ] && [ -z "$ERR" ] \
   && [ ! -e "$W/.milestone-config/triage-cache.json" ]; then ok; else
  no "write-bad-entries: rc=$RC out=[$OUT] err=[$ERR]"; fi

W="$(ws)"
run_write "$W" "$FIX/does-not-exist.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "SKIP${TAB}bad-entries" ] && [ -z "$ERR" ]; then ok; else
  no "write-missing-entries: rc=$RC out=[$OUT] err=[$ERR]"; fi

# A regular FILE occupying .milestone-config/ makes `mkdir -p` fail.
W="$(ws)"; : > "$W/.milestone-config"
run_write "$W" "$FIX/entries-two.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "SKIP${TAB}mkdir-failed" ] && [ -z "$ERR" ]; then ok; else
  no "write-mkdir-failed: rc=$RC out=[$OUT] err=[$ERR]"; fi

# A READ-ONLY .milestone-config/ lets mkdir succeed (it exists) and fails the
# write itself. Asserting stderr is EMPTY here is the point of the case: the
# .gitignore self-heal redirect also fails in this tree, and its open-failure
# leaks a bash diagnostic unless the redirect sits inside a silenced group.
# chmod 555 bites on the CI (Linux) leg; where perms don't bite (some Windows
# FS / root) the write succeeds and we skip rather than false-fail.
W="$(ws)"; mkdir -p "$W/.milestone-config"; chmod 555 "$W/.milestone-config"
run_write "$W" "$FIX/entries-two.json"
if [ "$OUT" = "OK${TAB}.milestone-config/triage-cache.json" ]; then
  ok  # read-only not enforced on this FS — the write-fail path is unreachable here
elif [ "$RC" -eq 0 ] && [ "$OUT" = "SKIP${TAB}write-failed" ] && [ -z "$ERR" ]; then ok; else
  no "write-failed: rc=$RC out=[$OUT] err=[$ERR]"; fi
chmod 755 "$W/.milestone-config" 2>/dev/null

# ---- bash-only: jq absent -> SKIP no-jq on every jq-backed subcommand --------
# The pwsh twin has no counterpart: it needs no external tool at all, so it can
# never reach this record. `query` is asserted to still work, because it is pure
# text generation and must not be gated on a dependency it does not use.
W="$(ws)"
for subcmd in lookup check-edges write; do
  got="$(PATH=/nonexistent "$BASH_BIN" "$SCRIPT" "$subcmd" "$W" "$FIX/entries-two.json" 2>"$ERRFILE")"; rcj=$?
  errj="$(cat "$ERRFILE")"
  if [ "$rcj" -eq 0 ] && [ "$got" = "SKIP${TAB}no-jq" ] && [ -z "$errj" ]; then ok; else
    no "no-jq/$subcmd: rc=$rcj out=[$got] err=[$errj]"; fi
done
got="$(PATH=/nonexistent "$BASH_BIN" "$SCRIPT" query keys acme widgets 7 2>"$ERRFILE")"; rcj=$?
if [ "$rcj" -eq 0 ] && [ -n "$got" ] && [ -z "$(cat "$ERRFILE")" ]; then ok; else
  no "no-jq/query: rc=$rcj out=[$got]"; fi

bespoke=$((pass + fail - case_count))
echo "triage-cache.sh: $pass passed, $fail failed (parsed $case_count TSV cases + $bespoke bespoke)"
[ "$fail" -eq 0 ]
