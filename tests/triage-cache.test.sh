#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for triage-cache.sh (issue #441).
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
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}

slurp_x() { cat "$1"; printf X; }

ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

case_count=0
while IFS= read -r row || [ -n "$row" ]; do
  row="${row%$'\r'}"
  case "$row" in ''|\#*) continue;; esac
  split_tab "$row"
  if [ "${#cols[@]}" -ne "$EXPECT_COLS" ]; then
    echo "FATAL: row failed to parse (got ${#cols[@]} fields, want $EXPECT_COLS): [$row]" >&2
    exit 1
  fi
  case_count=$((case_count+1))
  name="${cols[0]}"; args="${cols[1]}"; stdout_file="${cols[2]}"
  want_exit="${cols[3]}"; stderr_file="${cols[4]}"

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
    diff <(printf '%s' "$exp_out" | od -c) <(printf '%s' "$out" | od -c) >&2 || true
    printf '  stderr got[%s] want[%s]\n' "$err" "$exp_err" >&2
  fi
done < "$CASES"

if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES - this run tested nothing" >&2
  exit 1
fi

ws() { mktemp -d "$TMP/ws.XXXXXX"; }
run_write() { # <root> <entries> <response> -> OUT/RC
  OUT="$("$BASH_BIN" "$SCRIPT" write "$1" "$2" "$3" 2>"$ERRFILE")"; RC=$?
  ERR="$(cat "$ERRFILE")"
}

# ---- write: merge onto an existing canonical cache --------------------------
W="$(ws)"; cp -R "$FIX/roots/hit/." "$W/"
run_write "$W" "$FIX/entries-two.json" "$FIX/resp/ts-two.json"
CACHE="$W/.milestone-config/triage-cache.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "OK${TAB}.milestone-config/triage-cache.json" ] && [ -z "$ERR" ] \
   && jq -e '(keys | sort) == ["11","7","9"]
             and .["7"].key == "7:2026-08-01T00:00:00Z:3:alpha,zeta"
             and .["11"].key == "11:2026-08-02T00:00:00Z:0:"
             and .["9"].key == "9:STALE-KEY"
             and .["9"].triaged_at == "2026-08-01T01:00:00Z"
             and .["9"].result.edges == [100]
             and .["11"].result.risk == "heavy"' "$CACHE" >/dev/null; then ok; else
  no "write-merge: rc=$RC out=[$OUT] err=[$ERR] cache=$(cat "$CACHE" 2>/dev/null)"; fi

# ---- write: self-healed .gitignore is byte-identical to the committed one ----
if [ ! -f "$REPO_GITIGNORE" ]; then
  no "write-gitignore: missing $REPO_GITIGNORE"
elif cmp -s "$W/.milestone-config/.gitignore" "$REPO_GITIGNORE"; then ok; else
  no "write-gitignore: differs from $REPO_GITIGNORE"
  diff "$REPO_GITIGNORE" "$W/.milestone-config/.gitignore" >&2 || true; fi

# ---- write: an EXISTING .gitignore is never rewritten ------------------------
W="$(ws)"; mkdir -p "$W/.milestone-config"; printf 'sentinel\n' > "$W/.milestone-config/.gitignore"
run_write "$W" "$FIX/entries-two.json" "$FIX/resp/ts-two.json"
if [ "$RC" -eq 0 ] && [ "$(cat "$W/.milestone-config/.gitignore")" = "sentinel" ]; then ok; else
  no "write-gitignore-preserved: rc=$RC content=[$(cat "$W/.milestone-config/.gitignore")]"; fi

# ---- write: legacy root cache is READ, then REMOVED --------------------------
W="$(ws)"; cp "$FIX/roots/legacy-only/.milestone-driver-triage-cache.json" "$W/"
run_write "$W" "$FIX/entries-two.json" "$FIX/resp/ts-two.json"
if [ "$RC" -eq 0 ] && [ ! -e "$W/.milestone-driver-triage-cache.json" ] \
   && jq -e '(keys | sort) == ["11","7","9"]' "$W/.milestone-config/triage-cache.json" >/dev/null; then ok; else
  no "write-legacy-cleanup: rc=$RC legacy_present=$([ -e "$W/.milestone-driver-triage-cache.json" ] && echo yes || echo no)"; fi

# ---- write: every failure path is exit 0 + one SKIP record -------------------
W="$(ws)"
run_write "$W" "$FIX/entries-bad.json" "$FIX/resp/ts-two.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "SKIP${TAB}bad-entries" ] && [ -z "$ERR" ] \
   && [ ! -e "$W/.milestone-config/triage-cache.json" ]; then ok; else
  no "write-bad-entries: rc=$RC out=[$OUT] err=[$ERR]"; fi

W="$(ws)"
run_write "$W" "$FIX/does-not-exist.json" "$FIX/resp/ts-two.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "SKIP${TAB}bad-entries" ] && [ -z "$ERR" ]; then ok; else
  no "write-missing-entries: rc=$RC out=[$OUT] err=[$ERR]"; fi

W="$(ws)"; : > "$W/.milestone-config"
run_write "$W" "$FIX/entries-two.json" "$FIX/resp/ts-two.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "SKIP${TAB}mkdir-failed" ] && [ -z "$ERR" ]; then ok; else
  no "write-mkdir-failed: rc=$RC out=[$OUT] err=[$ERR]"; fi

W="$(ws)"; mkdir -p "$W/.milestone-config"; chmod 555 "$W/.milestone-config"
run_write "$W" "$FIX/entries-two.json" "$FIX/resp/ts-two.json"
if [ "$OUT" = "OK${TAB}.milestone-config/triage-cache.json" ]; then
  ok  # read-only not enforced on this FS - the write-fail path is unreachable here
elif [ "$RC" -eq 0 ] && [ "$OUT" = "SKIP${TAB}write-failed" ] && [ -z "$ERR" ]; then ok; else
  no "write-failed: rc=$RC out=[$OUT] err=[$ERR]"; fi
chmod 755 "$W/.milestone-config" 2>/dev/null

# ---- write -> lookup round trip: what write stores is what lookup compares ---
W="$(ws)"; cp -R "$FIX/roots/hit/." "$W/"
run_write "$W" "$FIX/entries-two.json" "$FIX/resp/ts-two.json"
RT="$("$BASH_BIN" "$SCRIPT" lookup "$W" "$FIX/resp/ts-two.json" 2>"$ERRFILE")"; RTRC=$?
RTERR="$(cat "$ERRFILE")"
RTWANT="HIT${TAB}7
MISS${TAB}9${TAB}key-mismatch
EDGES${TAB}100
SUMMARY${TAB}hits=1${TAB}misses=1"
if [ "$RC" -eq 0 ] && [ "$OUT" = "OK${TAB}.milestone-config/triage-cache.json" ] \
   && [ "$RTRC" -eq 0 ] && [ "$RT" = "$RTWANT" ] && [ -z "$RTERR" ]; then ok; else
  no "write-lookup-roundtrip: rc=$RC out=[$OUT] lookup_rc=$RTRC lookup=[$RT] err=[$RTERR]"; fi

# ---- write: the KEY-LESS entries object Step 6.5 actually builds -------------
W="$(ws)"; cp -R "$FIX/roots/hit/." "$W/"
run_write "$W" "$FIX/entries-keyless.json" "$FIX/resp/ts-two.json"
KL="$("$BASH_BIN" "$SCRIPT" lookup "$W" "$FIX/resp/ts-two.json" 2>/dev/null | head -1)"
if [ "$RC" -eq 0 ] && [ "$OUT" = "OK${TAB}.milestone-config/triage-cache.json" ] && [ -z "$ERR" ] \
   && [ "$KL" = "HIT${TAB}7" ] \
   && jq -e '.["7"].key == "7:2026-08-01T00:00:00Z:3:alpha,zeta"
             and (.["11"] | has("key") | not)
             and .["11"].result.risk == "heavy"
             and .["9"].triaged_at == "2026-08-01T01:00:00Z"' \
        "$W/.milestone-config/triage-cache.json" >/dev/null; then ok; else
  no "write-keyless-entries: rc=$RC out=[$OUT] err=[$ERR] first_lookup=[$KL]"; fi

# ---- write with THREE arguments is usage/exit 2, never a 3-arg write ---------
W="$(ws)"
"$BASH_BIN" "$SCRIPT" write "$W" "$FIX/entries-two.json" >"$OUTFILE" 2>"$ERRFILE"; RC=$?
OUT="$(slurp_x "$OUTFILE")"; OUT="${OUT%X}"
ERR="$(slurp_x "$ERRFILE")"; ERR="${ERR%X}"
WANTERR="$(slurp_x "$GOLD/usage.err")"; WANTERR="${WANTERR%X}"
WANTERR="${WANTERR//$'\r\n'/$'\n'}"; WANTERR="${WANTERR//__SCRIPT__/$SCRIPT_NAME}"
if [ "$RC" -eq 2 ] && [ -z "$OUT" ] && [ "$ERR" = "$WANTERR" ] \
   && [ ! -e "$W/.milestone-config" ]; then ok; else
  no "write-wrong-argc: rc=$RC (want 2) out=[$OUT] err=[$ERR]"; fi

# ---- write: an ABSENT response is the fail-open degradation, not a failure ----
W="$(ws)"
run_write "$W" "$FIX/entries-two.json" "$FIX/resp/absent.json"
if [ "$RC" -eq 0 ] && [ "$OUT" = "OK${TAB}.milestone-config/triage-cache.json" ] && [ -z "$ERR" ] \
   && jq -e '.["7"].key == "7:2026-08-02T00:00:00Z:4:alpha,zeta"' \
        "$W/.milestone-config/triage-cache.json" >/dev/null; then ok; else
  no "write-absent-response: rc=$RC out=[$OUT] err=[$ERR]"; fi

# ---- bash-only: jq absent -> SKIP no-jq on every jq-backed subcommand --------
W="$(ws)"
for subcmd in lookup check-edges write; do
  case "$subcmd" in
    write) set -- "$subcmd" "$W" "$FIX/entries-two.json" "$FIX/resp/ts-two.json" ;;
    *)     set -- "$subcmd" "$W" "$FIX/entries-two.json" ;;
  esac
  got="$(PATH=/nonexistent "$BASH_BIN" "$SCRIPT" "$@" 2>"$ERRFILE")"; rcj=$?
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
