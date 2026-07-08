#!/usr/bin/env bash
# milestone-driver — cache-aware cost-record helper (issue #320).
#
# Writes ONE JSON cost record per invocation to the gitignored per-clone scratch
# dir .milestone-config/.runtime/cost-records/ (relative to the CURRENT WORKING
# DIRECTORY, like render-daemon's .runtime/ state file). Deterministic,
# cross-platform, and NON-GATING: downstream #322 wires it into run-end.
#
# Input contract (stdin JSON, read ONCE — mirrors scripts/extract-version.sh:13):
#   {"runId":"<str>", "wallClockSeconds":<num>, "tiers":{"<tier>":{
#     "inputTokens":n,"outputTokens":n,"cacheReadTokens":n,"cacheWriteTokens":n}},
#    "provenanceNote":"<optional str>"}
#   Any OMITTED (or null) token/wallClock field defaults to 0; absent tiers -> {}.
#   A PRESENT-but-non-numeric token/wallClock value is MALFORMED (fail-open).
#
# Rate snapshot (hardcoded — NOT read from disk; source: kenmulford/milestone-suite
#   benchmarks/after/RESULTS.md ~lines 100-111, as-of 2026-07):
#     Opus 4.8  $5 in / $25 out per MTok ; Sonnet 4.6 $3 / $15.
#     cache-write rate = 1.25 x tier input rate ; cache-read = 0.1 x tier input rate.
#   Per-tier costUsd = (in*inRate + out*outRate + cWrite*inRate*1.25
#                       + cRead*inRate*0.1) / 1000000. Total = sum of PRICED tiers
#   only (rate-table keys: exactly opus + sonnet). Unknown tiers -> unpricedTiers,
#   excluded from costUsd, one stderr note each.
#
# Fail-open (mirrors scripts/extract-version.sh:11 emit_none; always exit 0 —
#   .project/design-philosophy.md#Error & failure philosophy): on empty/malformed
#   stdin, present-but-non-numeric token/wallClock, jq unavailable, empty/missing/
#   non-string runId, or an uncreatable/unwritable cost-records/ dir -> write NO
#   record, print EXACTLY ONE stderr diagnostic, exit 0. NEVER a non-zero exit.
#
# Dependency: jq (the cross-platform nonNegotiable already permits it); no new dep.
set -u
# Byte-deterministic string handling (mirrors extract-version.sh:10) so the
# filename sanitize stays aligned with the pwsh UTF-16 twin.
export LC_ALL=C

# fail-open: one stderr line, no record, exit 0.
fail() { printf 'write-cost-record: %s\n' "$*" >&2; exit 0; }

# rateSnapshot provenance base (single-quoted so $ is literal). Byte-identical to
# the .ps1 twin and both test runners (behavior-identical contract).
RATE_BASE='Opus 4.8 $5/$25 per MTok in/out; Sonnet 4.6 $3/$15 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.1x tier input rate; source: kenmulford/milestone-suite benchmarks/after/RESULTS.md, as-of 2026-07'

input="$(cat)"
[ -n "$input" ] || fail "empty stdin — no record written"
command -v jq >/dev/null 2>&1 || fail "jq is required but not on PATH — no record written"

# now_iso -> current time as ISO-8601 UTC (Zulu) — mirrors render-daemon.sh:173.
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
WRITTEN_AT="$(now_iso)"

# Build the record + the unpriced-tier name list in ONE jq pass. jq ERRORS
# (nonzero) on: unparseable JSON, an empty/missing/non-string runId, or any
# present-but-non-numeric token/wallClock value (numify) — all of which collapse
# to the single fail-open path below. Output is a wrapper {unpriced:[...],
# record:{...}} (mirrors render-daemon.sh:176-182 jq -n --arg/--argjson construction).
PROG='
def numify(v): if v == null then 0 elif (v|type)=="number" then v else error("nonnumeric") end;
def toks(t): { inputTokens: numify(t.inputTokens), outputTokens: numify(t.outputTokens),
               cacheReadTokens: numify(t.cacheReadTokens), cacheWriteTokens: numify(t.cacheWriteTokens) };
def tcost(t; r): ( numify(t.inputTokens) * r.in
                 + numify(t.outputTokens) * r.out
                 + numify(t.cacheWriteTokens) * (r.in * 1.25)
                 + numify(t.cacheReadTokens) * (r.in * 0.1) ) / 1000000;
({"opus":{"in":5,"out":25},"sonnet":{"in":3,"out":15}}) as $rates
| (if (.runId|type)=="string" and (.runId|length) > 0 then . else error("badrunid") end)
| . as $root
| ((.tiers // {}) | to_entries) as $entries
| {
    unpriced: [ $entries[] | select($rates[.key] == null) | .key ],
    record: {
      runId: $root.runId,
      writtenAt: $writtenAt,
      wallClockSeconds: numify($root.wallClockSeconds),
      costUsd: ( reduce ($entries[] | select($rates[.key] != null)) as $e (0; . + tcost($e.value; $rates[$e.key])) ),
      tiers: ( reduce ($entries[] | select($rates[.key] != null)) as $e ({};
                 . + { ($e.key): (toks($e.value) + { costUsd: tcost($e.value; $rates[$e.key]) }) } ) ),
      unpricedTiers: ( reduce ($entries[] | select($rates[.key] == null)) as $e ({};
                 . + { ($e.key): toks($e.value) } ) ),
      rateSnapshot: ( $rateBase
                    + (if ($root.provenanceNote|type)=="string" and ($root.provenanceNote|length) > 0
                       then "; note: " + $root.provenanceNote else "" end) )
    }
  }'
wrapper="$(printf '%s' "$input" | jq \
            --arg writtenAt "$WRITTEN_AT" --arg rateBase "$RATE_BASE" \
            "$PROG" 2>/dev/null)" \
  || fail "malformed input (unparseable JSON, missing/empty runId, or non-numeric token/wallClock) — no record written"

# Sanitize runId for the FILENAME only (raw runId stays verbatim in the body):
# map every byte outside [A-Za-z0-9._-] to '-' (tr -c complements the set; printf
# adds no trailing byte, so no spurious trailing dash). Byte-wise under LC_ALL=C.
# `tr -d '\r'` strips the CR that jq's Windows build text-adds when it maps '\n' ->
# CRLF on stdout (a bare $(...) strips only trailing '\n', not '\r', so without this
# a normal runId could pick up a trailing '-' on a non-msys Windows bash).
# Parity scope: for realistic runIds (plain identifiers — the AC examples are
# "run-happy", "run/1 x") the sanitized filename is byte-identical to the pwsh
# UTF-8-byte twin. A runId containing a RAW CR/LF byte is pathological and NOT
# guaranteed filename-identical across twins (jq -r emits a data CR verbatim, which
# this tr also drops, whereas the pwsh byte loop maps it to '-'); it does not matter
# — filenames already differ by the unique nonce, and the record BODY (JSON mode,
# where jq escapes any CR as \r) stays byte-identical across both twins.
runId_raw="$(printf '%s' "$wrapper" | jq -r '.record.runId' | tr -d '\r')"
sanitized="$(printf '%s' "$runId_raw" | tr -c 'A-Za-z0-9._-' '-')"

# Filename: <sanitized>-<UTC-unix-seconds>-<nonce>.json. Nonce mirrors the
# existing per-run pattern (render-daemon.sh:236): $$-$(date +%s)-$RANDOM.
ts="$(date -u +%s)"
nonce="$$-$(date +%s)-$RANDOM"
dir=".milestone-config/.runtime/cost-records"
rel="$dir/${sanitized}-${ts}-${nonce}.json"

# Create the scratch dir (mirrors render-daemon.sh:177,252). Uncreatable /
# unwritable -> fail-open.
mkdir -p "$dir" 2>/dev/null || fail "cannot create $dir — no record written"

# Wrap the write in a group so the redirect's OWN open-failure (e.g. an existing
# read-only cost-records/ dir, where mkdir -p succeeds but `> "$rel"` cannot open)
# is swallowed by the group's 2>/dev/null instead of leaking a second bash
# diagnostic to real fd2 — exactly ONE fail-open line either way. The `tr -d '\r'`
# makes the record LF-only even where jq's Windows build text-maps '\n' -> CRLF on
# stdout (jq escapes any literal CR inside a string as \r, so only translated line-
# ending CRs are stripped, never record data) — byte-parity with the LF-forcing
# pwsh twin (write-cost-record.ps1 ConvertTo-Json normalization).
if ! { printf '%s' "$wrapper" | jq '.record' | tr -d '\r' > "$rel"; } 2>/dev/null; then
  fail "cannot write record to $rel — no record written"
fi

# Record is written — NOW emit one stderr note per unpriced tier. Emitting AFTER the
# write (not before) guarantees a write fail-open above stays a SINGLE stderr line,
# never note(s) + the fail line. `tr -d '\r'` drops jq's Windows CRLF so a tier name
# carries no stray CR; no empty-name guard, so a (pathological) empty-string tier key
# still yields exactly one note — parity with the pwsh foreach.
while IFS= read -r t; do
  printf "write-cost-record: tier '%s' has no rate table entry — recorded under unpricedTiers, excluded from costUsd\n" "$t" >&2
done < <(printf '%s' "$wrapper" | jq -r '.unpriced[]' | tr -d '\r')

printf '%s\n' "$rel"
exit 0
