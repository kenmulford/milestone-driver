#!/usr/bin/env bash
# milestone-driver — behavior matrix runner for write-cost-record.sh (issue #320).
# Drives the cache-aware cost-record helper and asserts every acceptance
# criterion by FIELD CONTENT (jq) plus the fail-open stderr/exit contract:
# happy path (both tiers, exact dollar math), omitted-fields -> zeros,
# empty-state, empty/malformed stdin, non-numeric token/wallClock, missing /
# empty runId, unknown (unpriced) tier, provenanceNote present/absent/non-string,
# and runId sanitization in the filename vs verbatim in the body.
# The .sh and .ps1 runners assert the SAME field + rateSnapshot contract
# (cross-impl parity), mirroring tests/render-daemon.test.{sh,ps1}. Each case runs
# the helper with cwd set to a fresh mktemp workspace so cost-records/ lands there
# (test isolation — .project/environment.md#Data stores).
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/write-cost-record.sh"
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }

# The rateSnapshot provenance base string (single-quoted so $ is literal). Must be
# byte-identical to scripts/write-cost-record.sh and the .ps1 twin + its test.
BASE='Opus 4.8 $5/$25 per MTok in/out; Sonnet 4.6 $3/$15 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.1x tier input rate; source: kenmulford/milestone-suite benchmarks/after/RESULTS.md, as-of 2026-07'

pass=0; fail=0
ok() { pass=$((pass+1)); }
no() { fail=$((fail+1)); printf 'FAIL %s\n' "$*" >&2; }

ROOT="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/wcr.$$")"; mkdir -p "$ROOT"
trap 'rm -rf "$ROOT"' EXIT

# run_case <json> — run the helper with a fresh cwd; sets OUT/ERR/RC/WS.
run_case() {
  WS="$(mktemp -d "$ROOT/case.XXXXXX")"
  OUT="$(cd "$WS" && printf '%s' "$1" | bash "$SCRIPT" 2>"$WS/.stderr")"; RC=$?
  ERR="$(cat "$WS/.stderr" 2>/dev/null)"
}
errlines() { printf '%s' "$ERR" | grep -c . ; }
recfile()  { ls "$WS/.milestone-config/.runtime/cost-records/"*.json 2>/dev/null | head -1; }
no_record() { [ -z "$(recfile)" ]; }

# ---- happy path: both priced tiers, exact dollar math ----------------------
# Token counts chosen to yield exactly-representable dollar values:
#   opus:   400000 in, 40000 out, 160000 cWrite, 2000000 cRead
#           (2.0 + 1.0 + 1.0 + 1.0) = 5.0
#   sonnet: 1000000 in, 200000 out, 800000 cWrite, 10000000 cRead
#           (3.0 + 3.0 + 3.0 + 3.0) = 12.0   -> total 17.0
run_case '{"runId":"run-happy","wallClockSeconds":42,"tiers":{"opus":{"inputTokens":400000,"outputTokens":40000,"cacheReadTokens":2000000,"cacheWriteTokens":160000},"sonnet":{"inputTokens":1000000,"outputTokens":200000,"cacheReadTokens":10000000,"cacheWriteTokens":800000}}}'
rec="$(recfile)"
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ -n "$rec" ] \
   && printf '%s' "$OUT" | grep -Eq 'cost-records/run-happy-[0-9]+-.+\.json' \
   && [ -f "$WS/$OUT" ] \
   && jq -e '.runId=="run-happy" and .wallClockSeconds==42 and .costUsd==17
             and .tiers.opus.inputTokens==400000 and .tiers.opus.outputTokens==40000
             and .tiers.opus.cacheReadTokens==2000000 and .tiers.opus.cacheWriteTokens==160000
             and .tiers.opus.costUsd==5
             and .tiers.sonnet.costUsd==12
             and (.unpricedTiers|length)==0
             and (.writtenAt|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' "$rec" >/dev/null; then
  # rateSnapshot must equal the base string exactly (no note suffix here).
  snap="$(jq -r '.rateSnapshot' "$rec")"
  if [ "$snap" = "$BASE" ]; then ok; else no "happy-snapshot: got [$snap]"; fi
else
  no "happy: rc=$RC err=[$ERR] out=[$OUT] rec=$rec"
fi

# ---- runId sanitization: filename sanitized, body verbatim -----------------
run_case '{"runId":"run/1 x","tiers":{"opus":{"inputTokens":1000000}}}'
rec="$(recfile)"
if [ "$RC" -eq 0 ] && [ -n "$rec" ] \
   && printf '%s' "$OUT" | grep -Eq 'cost-records/run-1-x-[0-9]+-.+\.json' \
   && jq -e '.runId=="run/1 x" and .tiers.opus.costUsd==5' "$rec" >/dev/null; then ok; else
  no "sanitize: rc=$RC out=[$OUT] rec=$rec runId=$(jq -r '.runId' "$rec" 2>/dev/null)"; fi

# ---- omitted wallClock / tier / token-fields -> zeros ----------------------
run_case '{"runId":"run-omit","tiers":{"opus":{"inputTokens":1000000}}}'
rec="$(recfile)"
if [ "$RC" -eq 0 ] && [ -n "$rec" ] \
   && jq -e '.wallClockSeconds==0 and .costUsd==5
             and .tiers.opus.inputTokens==1000000 and .tiers.opus.outputTokens==0
             and .tiers.opus.cacheReadTokens==0 and .tiers.opus.cacheWriteTokens==0
             and .tiers.opus.costUsd==5' "$rec" >/dev/null; then ok; else
  no "omit-zeros: rc=$RC rec=$rec"; fi

# ---- empty-state: omitted fields -> zeros present in record ----------------
run_case '{"runId":"run-empty"}'
rec="$(recfile)"
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ -n "$rec" ] \
   && jq -e '.runId=="run-empty" and .wallClockSeconds==0 and .costUsd==0
             and (.tiers|length)==0 and (.unpricedTiers|length)==0
             and has("rateSnapshot") and has("writtenAt")' "$rec" >/dev/null; then ok; else
  no "empty-state: rc=$RC err=[$ERR] rec=$rec"; fi

# ---- fail-open cases: exactly one stderr line, NO record, exit 0 -----------
fail_open() { # <label> <json>
  run_case "$2"
  if [ "$RC" -eq 0 ] && [ "$(errlines)" -eq 1 ] && no_record; then ok; else
    no "$1: rc=$RC errlines=$(errlines) record=$(recfile)"; fi
}
fail_open "empty-stdin"        ''
fail_open "malformed-json"     '{not valid json'
fail_open "nonnumeric-token"   '{"runId":"x","tiers":{"opus":{"inputTokens":"lots"}}}'
fail_open "nonnumeric-wall"    '{"runId":"x","wallClockSeconds":"soon"}'
fail_open "missing-runid"      '{"wallClockSeconds":1}'
fail_open "empty-runid"        '{"runId":""}'
fail_open "nonstring-runid"    '{"runId":123}'

# ---- unknown (unpriced) tier -----------------------------------------------
# opus priced (in costUsd + tiers); weirdmodel recorded raw under unpricedTiers,
# excluded from costUsd, with a one-line stderr note naming it.
run_case '{"runId":"run-unpriced","tiers":{"opus":{"inputTokens":1000000},"weirdmodel":{"inputTokens":5,"outputTokens":6,"cacheReadTokens":7,"cacheWriteTokens":8}}}'
rec="$(recfile)"
if [ "$RC" -eq 0 ] && [ -n "$rec" ] \
   && printf '%s' "$ERR" | grep -q 'weirdmodel' \
   && jq -e '.costUsd==5 and (.tiers|has("weirdmodel")|not) and .tiers.opus.costUsd==5
             and .unpricedTiers.weirdmodel.inputTokens==5 and .unpricedTiers.weirdmodel.outputTokens==6
             and .unpricedTiers.weirdmodel.cacheReadTokens==7 and .unpricedTiers.weirdmodel.cacheWriteTokens==8
             and (.unpricedTiers.weirdmodel|has("costUsd")|not)' "$rec" >/dev/null; then ok; else
  no "unpriced: rc=$RC err=[$ERR] rec=$rec"; fi

# ---- provenanceNote present -> "; note: <note>" suffix ---------------------
run_case '{"runId":"run-note","provenanceNote":"manual backfill"}'
rec="$(recfile)"
snap="$(jq -r '.rateSnapshot' "$rec" 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ -n "$rec" ] && [ "$snap" = "$BASE; note: manual backfill" ]; then ok; else
  no "note-present: rc=$RC snap=[$snap]"; fi

# ---- provenanceNote non-string -> treated as absent (byte-identical base) ---
run_case '{"runId":"run-badnote","provenanceNote":123}'
rec="$(recfile)"
snap="$(jq -r '.rateSnapshot' "$rec" 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ -z "$ERR" ] && [ -n "$rec" ] && [ "$snap" = "$BASE" ]; then ok; else
  no "note-nonstring: rc=$RC err=[$ERR] snap=[$snap]"; fi

# ---- (F7a) cost-records path occupied by a FILE -> dir uncreatable -> fail-open
# Pre-create a regular FILE where the cost-records/ dir must go, so `mkdir -p`
# fails (cross-platform: New-Item -Directory then Set-Content also fail open in
# the pwsh twin). Assert exactly one stderr line, NO record, exit 0.
WS="$(mktemp -d "$ROOT/case.XXXXXX")"
mkdir -p "$WS/.milestone-config/.runtime"
: > "$WS/.milestone-config/.runtime/cost-records"
OUT="$(cd "$WS" && printf '%s' '{"runId":"run-nodir","tiers":{"opus":{"inputTokens":1000000}}}' | bash "$SCRIPT" 2>"$WS/.stderr")"; RC=$?
ERR="$(cat "$WS/.stderr" 2>/dev/null)"
if [ "$RC" -eq 0 ] && [ "$(errlines)" -eq 1 ] && [ ! -d "$WS/.milestone-config/.runtime/cost-records" ]; then ok; else
  no "uncreatable-dir: rc=$RC errlines=$(errlines) out=[$OUT] err=[$ERR]"; fi

# ---- (F7b) non-object tier value -> malformed -> fail-open (F5 parity) -------
# jq errors indexing a number (42.inputTokens); the pwsh twin now matches via the
# F5 non-object-tier guard. Both: one stderr line, no record, exit 0.
run_case '{"runId":"x","tiers":{"opus":42}}'
if [ "$RC" -eq 0 ] && [ "$(errlines)" -eq 1 ] && no_record; then ok; else
  no "nonobject-tier: rc=$RC errlines=$(errlines) record=$(recfile)"; fi

# ---- tiny sub-1e-4 costUsd asserted by NUMERIC VALUE (not float bytes) -------
# opus outputTokens=2 -> 2*25/1e6 = 5e-05 (avoids the inexact 0.1 cache-read
# factor, so the value is exactly representable). The ON-DISK float form is jq-
# version-dependent (jq 1.8 writes `0.00005`, jq 1.7 wrote `5e-05`) — both valid
# JSON for the same value — so assert the parsed NUMBER, never the bytes.
run_case '{"runId":"run-tiny","tiers":{"opus":{"outputTokens":2}}}'
rec="$(recfile)"
if [ "$RC" -eq 0 ] && [ -n "$rec" ] \
   && jq -e '.costUsd == 5e-05 and .tiers.opus.costUsd == 5e-05' "$rec" >/dev/null; then ok; else
  no "tiny-sci: rc=$RC costUsd=$(jq -r '.costUsd' "$rec" 2>/dev/null)"; fi

# ---- fail-open AT THE WRITE + unpriced tier -> STILL exactly one stderr line --
# An unpriced tier normally prints a note; but when the RECORD WRITE fails open the
# note MUST NOT precede the fail line — the contract is exactly ONE stderr line.
# Use a READ-ONLY cost-records DIR so `mkdir -p` succeeds (dir exists) but the write
# (`> "$rel"`) fails AFTER the unpriced tier is computed — this reaches the write-
# open fail-open branch and exercises the emit-notes-AFTER-write ordering (a FILE at
# the path would instead fail at mkdir, before the notes/write). chmod 555 bites on
# the CI (Linux) leg; where perms don't bite (some Windows FS / root) the record
# writes and we skip rather than false-fail.
WS="$(mktemp -d "$ROOT/case.XXXXXX")"
mkdir -p "$WS/.milestone-config/.runtime/cost-records"
chmod 555 "$WS/.milestone-config/.runtime/cost-records"
OUT="$(cd "$WS" && printf '%s' '{"runId":"r","tiers":{"gpt":{"inputTokens":1}}}' | bash "$SCRIPT" 2>"$WS/.stderr")"; RC=$?
ERR="$(cat "$WS/.stderr" 2>/dev/null)"
if [ -n "$(recfile)" ]; then
  ok  # read-only not enforced on this FS — write-fail-open path unreachable here; skip
elif [ "$RC" -eq 0 ] && [ "$(errlines)" -eq 1 ]; then ok; else
  no "failopen-write-unpriced-oneline: rc=$RC errlines=$(errlines) err=[$ERR]"; fi
chmod 755 "$WS/.milestone-config/.runtime/cost-records" 2>/dev/null

# ---- runId / provenanceNote with `<digit>E<digit>` preserved VERBATIM --------
# Guards the twins against any exponent-normalizing rewrite bleeding into string
# fields (would turn runId "1E2" -> "1e2"). Body must carry the raw values.
run_case '{"runId":"1E2","provenanceNote":"batch 2E10 rows"}'
rec="$(recfile)"
if [ "$RC" -eq 0 ] && [ -n "$rec" ] \
   && jq -e '.runId == "1E2" and (.rateSnapshot | test("; note: batch 2E10 rows$"))' "$rec" >/dev/null; then ok; else
  no "verbatim-E: rc=$RC runId=$(jq -r '.runId' "$rec" 2>/dev/null) snap=$(jq -r '.rateSnapshot' "$rec" 2>/dev/null)"; fi

echo "write-cost-record.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
