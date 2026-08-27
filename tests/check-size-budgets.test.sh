#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for check-size-budgets.sh (issue #295).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/check-size-budgets.sh"
FIX="tests/fixtures/check-size-budgets"
GOLD="$ROOT/$FIX/_expected"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }

declare -a CASES=(
  "at-ceiling|0"
  "one-over|1"
  "line-flat-byte-over|1"
  "byte-flat-word-over|1"
  "missing-file|1"
  "missing-closure-member|1"
)

pass=0; fail=0
cd "$ROOT"
for spec in "${CASES[@]}"; do
  IFS='|' read -r name wantExit <<< "$spec"
  exp="$GOLD/$name.txt"
  [ -f "$exp" ] || { echo "FAIL $name: missing golden $exp" >&2; fail=$((fail+1)); continue; }
  got="$(bash "$SCRIPT" "$FIX/$name" 2>&1)"; rc=$?
  want="$(tr -d '\r' < "$exp")"
  if [ "$got" = "$want" ] && [ "$rc" -eq "$wantExit" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL $name: rc=$rc (want $wantExit)" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2 || true
  fi
done

GUARD_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_guard.$$")"
GUARD_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_guard_err.$$")"
SWAP_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_swap.$$")"
MAL_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_mal.$$")"
MAL_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_mal_err.$$")"
EMPTY_SCRIPT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_empty.$$")"
EMPTY_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/csb_empty_err.$$")"
EXC_TREE="$(mktemp -d 2>/dev/null || { d="${TMPDIR:-/tmp}/csb_exc.$$"; mkdir -p "$d"; echo "$d"; })"
trap 'rm -f "$GUARD_SCRIPT" "$GUARD_ERR" "$SWAP_SCRIPT" "$MAL_SCRIPT" "$MAL_ERR" "$EMPTY_SCRIPT" "$EMPTY_ERR"; rm -rf "$EXC_TREE"' EXIT

# --- parity-guard: the length-parity refusal (issue #399) ------------------
GUARD_GOLD="$GOLD/parity-guard.stderr.txt"
if [ ! -f "$GUARD_GOLD" ]; then
  echo "FAIL parity-guard: missing golden $GUARD_GOLD" >&2; fail=$((fail+1))
else
  awk '!hit && /^(skills|agents)\// && NF == 4 { $2 = "-"; hit = 1 }
       { print }' "$SCRIPT" > "$GUARD_SCRIPT"
  guard_out="$(bash "$GUARD_SCRIPT" "$FIX/at-ceiling" 2>"$GUARD_ERR")"; grc=$?
  guard_err="$(tr -d '\r' < "$GUARD_ERR")"
  guard_want="$(tr -d '\r' < "$GUARD_GOLD")"
  if [ -z "$guard_out" ] && [ "$grc" -eq 1 ] && [ "$guard_err" = "$guard_want" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL parity-guard: rc=$grc (want 1), stdout=[$guard_out] (want empty)" >&2
    diff <(printf '%s\n' "$guard_want") <(printf '%s\n' "$guard_err") >&2 || true
  fi
fi

# --- positional-desync: a moved row carries its own ceilings (issue #428) ---
SWAP_GOLD="$GOLD/at-ceiling.txt"
if [ ! -f "$SWAP_GOLD" ]; then
  echo "FAIL positional-desync: missing golden $SWAP_GOLD" >&2; fail=$((fail+1))
else
  awk '{ line[NR] = $0
         if ($1 == "agents/design-reviewer.md") a = NR
         if ($1 == "agents/implementer.md") b = NR }
       END { if (a && b) { t = line[a]; line[a] = line[b]; line[b] = t }
             for (n = 1; n <= NR; n++) print line[n] }' "$SCRIPT" > "$SWAP_SCRIPT"
  swap_out="$(bash "$SWAP_SCRIPT" "$FIX/at-ceiling" 2>&1)"; swap_rc=$?
  swap_want="$(tr -d '\r' < "$SWAP_GOLD")"
  if [ "$swap_rc" -eq 0 ] && [ "$swap_out" != "$swap_want" ] &&
     [ "$(printf '%s\n' "$swap_out" | sort)" = "$(printf '%s\n' "$swap_want" | sort)" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL positional-desync: rc=$swap_rc (want 0); the two swapped rows must reorder the stream, not reattribute ceilings" >&2
    if [ "$swap_out" = "$swap_want" ]; then
      echo "  the row swap was a no-op - re-key it to the current table shape" >&2
    fi
    diff <(printf '%s\n' "$swap_want" | sort) <(printf '%s\n' "$swap_out" | sort) >&2 || true
  fi
fi

# --- malformed-row parity: the other three single-row edits (issue #428) ----
mal_refusal="$(sed 's/CEILINGS(38), BYTE_CEILINGS(39) and WORD_CEILINGS(39)/CEILINGS(39), BYTE_CEILINGS(39) and WORD_CEILINGS(38)/' "$GUARD_GOLD" | tr -d '\r')"
wide_stream="$(sed -e '/skills\/setup\/SKILL.md/ s#/28000#/99999999999#' \
                   -e '/skills\/setup\/SKILL.md/ s#/4000#/99999999999#' \
                   "$GOLD/at-ceiling.txt" | tr -d '\r')"
for mal in short long wide; do
  case "$mal" in
    short) prog='!hit && /^(skills|agents)\// && NF == 4 { $0 = $1 " " $2 " " $3; hit = 1 } { print }'
           want_rc=1; want_out=''; want_err="$mal_refusal" ;;
    long)  prog='!hit && /^(skills|agents)\// && NF == 4 { $0 = $0 " 999"; hit = 1 } { print }'
           want_rc=1; want_out=''; want_err="$mal_refusal" ;;
    wide)  prog='!hit && /^(skills|agents)\// && NF == 4 { $0 = $1 " " $2 " 99999999999 99999999999"; hit = 1 } { print }'
           want_rc=0; want_out="$wide_stream"; want_err='' ;;
  esac
  awk "$prog" "$SCRIPT" > "$MAL_SCRIPT"
  mal_out="$(bash "$MAL_SCRIPT" "$FIX/at-ceiling" 2>"$MAL_ERR")"; mrc=$?
  mal_err="$(tr -d '\r' < "$MAL_ERR")"
  if [ "$mrc" -eq "$want_rc" ] && [ "$mal_out" = "$want_out" ] && [ "$mal_err" = "$want_err" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL malformed-row/$mal: rc=$mrc (want $want_rc)" >&2
    diff <(printf 'STDOUT\n%s\nSTDERR\n%s\n' "$want_out" "$want_err") \
         <(printf 'STDOUT\n%s\nSTDERR\n%s\n' "$mal_out" "$mal_err") >&2 || true
  fi
done

# --- empty-closure-table: no closures is a no-op, not an error (issue #491) --
empty_want="$(tr -d '\r' < "$GOLD/at-ceiling.txt" | grep -v '^CLOSURE	')"
awk '/^done <<.CLOSURE_TABLE.$/ { intbl = 1; print; next }
     /^CLOSURE_TABLE$/          { intbl = 0; print; next }
     intbl                      { next }
                                { print }' "$SCRIPT" > "$EMPTY_SCRIPT"
empty_out="$(bash "$EMPTY_SCRIPT" "$FIX/at-ceiling" 2>"$EMPTY_ERR")"; erc=$?
empty_err="$(tr -d '\r' < "$EMPTY_ERR")"
if [ "$erc" -eq 0 ] && [ "$empty_out" = "$empty_want" ] && [ -z "$empty_err" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  echo "FAIL empty-closure-table: rc=$erc (want 0), stderr=[$empty_err] (want empty)" >&2
  diff <(printf '%s\n' "$empty_want") <(printf '%s\n' "$empty_out") >&2 || true
fi

# --- excluded-untouched: the six branch-gated files are outside every closure
cp -R "$FIX/at-ceiling/." "$EXC_TREE/"
for x in skills/solve-milestone/parallel-waves.md \
         skills/solve-milestone/milestone-granularity.md \
         skills/solve-milestone/trello-sync.md \
         skills/solve-issue/async-mode.md \
         skills/solve-issue/md-epic-fanout.md \
         skills/triage/blocker-resolver-dispatch.md; do
  printf 'excluded branch gated padding words\n' >> "$EXC_TREE/$x"
done
exc_out="$(bash "$SCRIPT" "$EXC_TREE" 2>&1)"
exc_gold="$(tr -d '\r' < "$GOLD/at-ceiling.txt")"
exc_got_cl="$(printf '%s\n' "$exc_out"  | grep '^CLOSURE	' || true)"
exc_want_cl="$(printf '%s\n' "$exc_gold" | grep '^CLOSURE	' || true)"
exc_got_rest="$(printf '%s\n' "$exc_out"  | grep -v '^CLOSURE	' || true)"
exc_want_rest="$(printf '%s\n' "$exc_gold" | grep -v '^CLOSURE	' || true)"
if [ -n "$exc_want_cl" ] && [ "$exc_got_cl" = "$exc_want_cl" ] && [ "$exc_got_rest" != "$exc_want_rest" ]; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  echo "FAIL excluded-untouched: editing a branch-gated file must leave every CLOSURE line unchanged" >&2
  if [ "$exc_got_rest" = "$exc_want_rest" ]; then
    echo "  the perturbation was a no-op - re-key it to the current fixture tree" >&2
  fi
  diff <(printf '%s\n' "$exc_want_cl") <(printf '%s\n' "$exc_got_cl") >&2 || true
fi

echo "check-size-budgets.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
