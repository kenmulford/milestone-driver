#!/usr/bin/env bash
# milestone-driver - cache-aware cost-record helper (issue #320).
#
# Writes ONE JSON cost record per invocation to the gitignored per-clone scratch
# dir .milestone-config/.runtime/cost-records/ (relative to the CURRENT WORKING
# DIRECTORY, like render-daemon's .runtime/ state file). Deterministic,
# cross-platform, and NON-GATING: downstream #322 wires it into run-end.
#
# Input contract (stdin JSON, read ONCE), mirroring scripts/extract-version.sh (input="$(cat)";):
#   {"runId":"<str>", "wallClockSeconds":<num>, "tiers":{"<tier>":{
#     "inputTokens":n,"outputTokens":n,"cacheReadTokens":n,"cacheWriteTokens":n}},
#    "provenanceNote":"<optional str>"}
#   Any OMITTED (or null) token/wallClock field defaults to 0; absent tiers -> {}.
#   A PRESENT-but-non-numeric token/wallClock value is MALFORMED (fail-open).
#
# Rate snapshot (hardcoded - NOT read from disk; source:
#   https://platform.claude.com/docs/en/about-claude/pricing, as-of 2026-11-21):
#     Opus 5.5  $4 in / $20 out per MTok ; Sonnet 5.5 $2 / $10.
#     cache-write rate = 1.25 x tier input rate ; cache-read = 0.05 x tier input rate.
#   Per-tier costUsd = (in*inRate + out*outRate + cWrite*inRate*1.25
#                       + cRead*inRate*0.05) / 1000000. Total = sum of PRICED tiers
#   only (rate-table keys: exactly opus + sonnet). Unknown tiers -> unpricedTiers,
#   excluded from costUsd, one stderr note each.
#
# Fail-open (mirrors scripts/extract-version.sh (emit_none() { printf 'none' >&2) emit_none; always exit 0 -
#   .project/design-philosophy.md#Error & failure philosophy): on empty/malformed
#   stdin, present-but-non-numeric token/wallClock, jq unavailable, empty/missing/
#   non-string runId, or an uncreatable/unwritable cost-records/ dir -> write NO
#   record, print EXACTLY ONE stderr diagnostic, exit 0. NEVER a non-zero exit.
#
# Modes (issue: lean-loop D5 - the run-end record must survive context
# compaction, which erases the orchestrator's in-context <usage> sums):
#   (no args)              the original contract above - unchanged.
#   --append <runId>       stdin {"agent":"<str>","tier":"<str>","totalTokens":n,
#                           "durationMs":n} plus optional "steps",
#                           "stepsBeforeFirstEdit", "minutesToFirstEdit" (each
#                           kept only when present and non-null, so a four-field
#                           input yields today's line byte-for-byte; any other
#                           key, "minutes" included, is dropped because
#                           durationMs already carries the duration) ->
#                           appends ONE compact JSON line to
#                           .milestone-config/.runtime/usage/<sanitized-runId>.jsonl
#                           (create + append; never truncates). agent/tier
#                           required non-empty strings, tier stored lowercased
#                           (--finalize lowercases too); token/duration default 0,
#                           present-non-numeric is malformed. Prints the relative
#                           usage-file path. Fail-open exactly like the default
#                           mode: malformed input, missing runId arg, or an
#                           uncreatable dir -> one stderr line, no line written,
#                           exit 0.
#   --start <runId>        no stdin, no jq: writes the UTC time plus LF to
#                           .milestone-config/.runtime/usage/<sanitized-runId>.start
#                           only when that file is absent, so a rerun keeps the
#                           first start time. Prints the relative path. Fail-open
#                           like --append: missing runId arg, an uncreatable dir,
#                           or an unwritable file -> one stderr line, exit 0.
#   --finalize <runId> [<transcriptDir>]
#                           reads that whole .jsonl (no stdin) for `wallClockSeconds`
#                           (durationMs summed, over 1000) and `agents` (the raw
#                           per-line entries verbatim, in file order, for a per-agent
#                           durationMs breakdown the aggregate cannot give back), then
#                           runs the EXACT SAME costing pass as the default mode - one
#                           rate table, one cost record shape, everywhere. `tiers` come
#                           from one of two paths.
#                           Per-turn: every top-level agent-*.jsonl in <transcriptDir>
#                           (byte-sorted) whose first string `.timestamp` is at or after
#                           the first line of
#                           .milestone-config/.runtime/usage/<sanitized-runId>.start
#                           (%Y-%m-%dT%H:%M:%SZ, whole seconds) has its assistant turns'
#                           four `message.usage` counts summed per tier, each
#                           `message.id` once per file; a missing, null or non-numeric
#                           count is 0, `<synthetic>` is skipped, a model naming opus
#                           or sonnet is that tier, a missing model is `?`, any other
#                           id is its own tier and lands in unpricedTiers.
#                           provenanceNote `per-turn-transcript-sum`.
#                           Unsplit fallback: the usage lines' totalTokens summed per
#                           tier into `tiers.<t>.inputTokens` (a lower bound).
#                           provenanceNote `unsplit-total-as-input`, plus exactly one
#                           stderr line `write-cost-record: <reason> - using unsplit
#                           totals`, <reason> being one of: no transcript directory
#                           argument; transcript directory <dir> not found; no start
#                           file at <rel>; start file <rel> is not
#                           %Y-%m-%dT%H:%M:%SZ; no agent transcript at or after
#                           <start> in <dir>. A transcript pass that cannot complete
#                           takes the same path with reason `cannot sum the
#                           transcripts in <dir>`.
#                           Fail-open: missing runId arg, missing/empty/malformed usage
#                           file -> one stderr line, no record, exit 0.
#
# Dependency: jq (the cross-platform nonNegotiable already permits it); no new dep.
set -u
# Byte-deterministic string handling, mirroring scripts/extract-version.sh (export LC_ALL=C), so the
# filename sanitize stays aligned with the pwsh UTF-16 twin.
export LC_ALL=C

# fail-open: one stderr line, no record, exit 0.
fail() { printf 'write-cost-record: %s\n' "$*" >&2; exit 0; }

# rateSnapshot provenance base (single-quoted so $ is literal). Byte-identical to
# the .ps1 twin and both test runners (behavior-identical contract).
RATE_BASE='Opus 5.5 $4/$20 per MTok in/out; Sonnet 5.5 $2/$10 per MTok in/out; cache-write 1.25x tier input rate, cache-read 0.05x tier input rate; source: https://platform.claude.com/docs/en/about-claude/pricing, as-of 2026-11-21'

# sanitize_for_filename <str> -> map every byte outside [A-Za-z0-9._-] to '-'.
# One definition shared by the default mode's runId, --append, and --finalize,
# so the same runId always names the same usage file across all three.
sanitize_for_filename() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }

usage_dir=".milestone-config/.runtime/usage"

mode="${1:-}"

# ---- --append <runId>: one usage line per dispatch, its own short path -----
# Exits before the default-mode stdin contract below; nothing past this block
# applies to this mode.
if [ "$mode" = "--append" ]; then
  runid_arg="${2:-}"
  [ -n "$runid_arg" ] || fail "usage: write-cost-record.sh --append <runId> - no line appended"
  input="$(cat)"
  [ -n "$input" ] || fail "empty stdin - no line appended"
  command -v jq >/dev/null 2>&1 || fail "jq is required but not on PATH - no line appended"
  APPEND_PROG='
    def numify(v): if v == null then 0 elif (v|type)=="number" then v else error("nonnumeric") end;
    (if (.agent|type)=="string" and (.agent|length) > 0 then . else error("badagent") end)
    | (if (.tier|type)=="string" and (.tier|length) > 0 then . else error("badtier") end)
    | . as $in
    | { agent: .agent, tier: (.tier|ascii_downcase), totalTokens: numify(.totalTokens), durationMs: numify(.durationMs) }
      + (reduce ("steps", "stepsBeforeFirstEdit", "minutesToFirstEdit") as $k ({};
           if $in[$k] == null then . else . + { ($k): numify($in[$k]) } end))'
  line="$(printf '%s' "$input" | jq -c "$APPEND_PROG" 2>/dev/null)" \
    || fail "malformed input (unparseable JSON, missing/empty agent or tier, or non-numeric totalTokens/durationMs/steps/stepsBeforeFirstEdit/minutesToFirstEdit) - no line appended"
  rel="$usage_dir/$(sanitize_for_filename "$runid_arg").jsonl"
  mkdir -p "$usage_dir" 2>/dev/null || fail "cannot create $usage_dir - no line appended"
  if ! { printf '%s\n' "$line" | tr -d '\r' >> "$rel"; } 2>/dev/null; then
    fail "cannot append to $rel - no line appended"
  fi
  printf '%s\n' "$rel"
  exit 0
fi

# now_iso -> current time as ISO-8601 UTC (Zulu) - mirrors scripts/render-daemon.sh (now_iso() {).
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---- --start <runId>: record the run's start time once, its own short path --
# Exits before the stdin contracts below; nothing past this block applies to
# this mode. mkdir runs before the existence check so an occupied `usage` path
# reports "cannot create"; an existing start file is never rewritten.
if [ "$mode" = "--start" ]; then
  runid_arg="${2:-}"
  [ -n "$runid_arg" ] || fail "usage: write-cost-record.sh --start <runId> - no start time written"
  rel="$usage_dir/$(sanitize_for_filename "$runid_arg").start"
  mkdir -p "$usage_dir" 2>/dev/null || fail "cannot create $usage_dir - no start time written"
  if [ ! -e "$rel" ]; then
    { printf '%s\n' "$(now_iso)" > "$rel"; } 2>/dev/null || fail "cannot write $rel - no start time written"
  fi
  printf '%s\n' "$rel"
  exit 0
fi

# ---- --finalize <runId>: rebuild `input` from the usage file, then fall ----
# through into the SAME costing pipeline the default mode already runs below -
# one rate table, one cost-record shape, never a second copy of either.
finalize_agents=""
finalize_note=""
if [ "$mode" = "--finalize" ]; then
  runid_arg="${2:-}"
  [ -n "$runid_arg" ] || fail "usage: write-cost-record.sh --finalize <runId> - no record written"
  command -v jq >/dev/null 2>&1 || fail "jq is required but not on PATH - no record written"
  usage_file="$usage_dir/$(sanitize_for_filename "$runid_arg").jsonl"
  [ -s "$usage_file" ] || fail "no usage data at $usage_file - no record written"
  AGG_PROG='
    def numify(v): if v == null then 0 elif (v|type)=="number" then v else error("nonnumeric") end;
    [ .[] | (if (.agent|type)=="string" and (.agent|length) > 0 then . else error("badagent") end)
          | (if (.tier|type)=="string" and (.tier|length) > 0 then . else error("badtier") end)
          | { agent: .agent, tier: (.tier|ascii_downcase), totalTokens: numify(.totalTokens), durationMs: numify(.durationMs) }
    ] as $entries
    | (reduce $entries[] as $e ({}; .[$e.tier] += $e.totalTokens)) as $tierSums
    | (reduce $entries[] as $e (0; . + $e.durationMs)) as $totalMs
    | {
        input: {
          runId: $runId,
          wallClockSeconds: ($totalMs / 1000),
          tiers: ( reduce ($tierSums | to_entries[]) as $e ({}; . + { ($e.key): { inputTokens: $e.value } }) ),
          provenanceNote: "unsplit-total-as-input"
        },
        agents: $entries
      }'
  agg="$(jq -s --arg runId "$runid_arg" "$AGG_PROG" "$usage_file" 2>/dev/null)" \
    || fail "malformed usage data in $usage_file - no record written"
  input="$(printf '%s' "$agg" | jq -c '.input' 2>/dev/null)" \
    || fail "internal aggregation error over $usage_file - no record written"
  finalize_agents="$(printf '%s' "$agg" | jq -c '.agents' 2>/dev/null)" \
    || fail "internal aggregation error over $usage_file - no record written"

  # Per-turn path: replace the unsplit `input.tiers` with sums over the session's
  # agent transcripts. Any reason it cannot run keeps `input` as built above and is
  # held in finalize_note, printed after the record write so a failed write stays
  # one stderr line. Per-file jq, not one pass over all files: the first-timestamp
  # start test and the message.id dedup are both per file, and a file jq cannot
  # read or date prints nothing, so it simply does not match.
  tdir="${3:-}"
  start_rel="$usage_dir/$(sanitize_for_filename "$runid_arg").start"
  if [ -z "$tdir" ]; then
    finalize_note="no transcript directory argument"
  elif [ ! -d "$tdir" ]; then
    finalize_note="transcript directory $tdir not found"
  elif [ ! -f "$start_rel" ]; then
    finalize_note="no start file at $start_rel"
  else
    start_line="$(head -n 1 "$start_rel" 2>/dev/null | tr -d '\r')"
    # mirrors scripts/measure-dispatch.sh (def secs), which truncates fractional seconds
    # because jq's fromdate rejects them. ts($frac) is the one timestamp shape: whole
    # seconds for the start file, an optional fraction for a transcript, as in the .ps1 twin.
    TS_DEFS='
      def secs: sub("\\.[0-9]+"; "") | fromdate;
      def ts($frac): if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
                             + (if $frac then "(\\.[0-9]+)?" else "" end) + "Z$")
                     then secs else null end;'
    start_epoch="$(printf '%s\n' "$start_line" | jq -Rr "$TS_DEFS"'ts(false) | values' 2>/dev/null | tr -d '\r')"
    if [ -z "$start_epoch" ]; then
      finalize_note="start file $start_rel is not %Y-%m-%dT%H:%M:%SZ"
    else
      # The first object line with a string `.timestamp` gates the file: an unusable or
      # pre-start one breaks out before the rest is read. Turns are collected in the same
      # pass, so nothing is held but the dedup keys and the turns themselves.
      TURN_PROG="$TS_DEFS"'
        def num(v): if (v|type) == "number" then v else 0 end;
        label $skip
        | reduce (inputs | fromjson? | objects) as $e (
            {started: false, seen: {}, turns: []};
            (if .started or ($e.timestamp | type) != "string" then .
             else (($e.timestamp | ts(true)) as $t0
                   | if $t0 != null and $t0 >= $start then .started = true else break $skip end)
             end)
            | if $e.type == "assistant" and ($e.message|type) == "object"
                 and ($e.message.usage|type) == "object" then
                ($e.message.id | tojson) as $k
                | if .seen[$k] then .
                  else .seen[$k] = true
                    | ($e.message.model | if type == "string" then ascii_downcase else "?" end) as $m
                    | if $m == "<synthetic>" then .
                      else .turns += [{
                        tier: (if ($m|contains("opus")) then "opus" elif ($m|contains("sonnet")) then "sonnet" else $m end),
                        inputTokens: num($e.message.usage.input_tokens), outputTokens: num($e.message.usage.output_tokens),
                        cacheReadTokens: num($e.message.usage.cache_read_input_tokens),
                        cacheWriteTokens: num($e.message.usage.cache_creation_input_tokens)}]
                      end
                  end
              else . end)
        | select(.started) | .turns'
      SUM_PROG='
        reduce (.[][]) as $t ({};
          reduce ("inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens") as $k (.;
            .[$t.tier][$k] += $t[$k]))'
      outs=""
      for f in "$tdir"/agent-*.jsonl; do
        [ -f "$f" ] || continue
        out="$(jq -R -n -c --argjson start "$start_epoch" "$TURN_PROG" "$f" 2>/dev/null | tr -d '\r')"
        [ -n "$out" ] || continue
        outs="$outs$out
"
      done
      if [ -z "$outs" ]; then
        finalize_note="no agent transcript at or after $start_line in $tdir"
      elif sums="$(printf '%s' "$outs" | jq -s -c "$SUM_PROG" 2>/dev/null)" \
           && new_input="$(printf '%s' "$input" | jq -c --argjson tiers "$sums" \
                '.tiers = $tiers | .provenanceNote = "per-turn-transcript-sum"' 2>/dev/null)"; then
        input="$new_input"
      else
        finalize_note="cannot sum the transcripts in $tdir"
      fi
    fi
  fi
else
  input="$(cat)"
  [ -n "$input" ] || fail "empty stdin - no record written"
  command -v jq >/dev/null 2>&1 || fail "jq is required but not on PATH - no record written"
fi

WRITTEN_AT="$(now_iso)"

# Build the record + the unpriced-tier name list in ONE jq pass. jq ERRORS
# (nonzero) on: unparseable JSON, an empty/missing/non-string runId, or any
# present-but-non-numeric token/wallClock value (numify) - all of which collapse
# to the single fail-open path below. Output is a wrapper {unpriced:[...],
# record:{...}} (mirrors scripts/render-daemon.sh (write_state() {) jq -n --arg/--argjson construction).
PROG='
def numify(v): if v == null then 0 elif (v|type)=="number" then v else error("nonnumeric") end;
def toks(t): { inputTokens: numify(t.inputTokens), outputTokens: numify(t.outputTokens),
               cacheReadTokens: numify(t.cacheReadTokens), cacheWriteTokens: numify(t.cacheWriteTokens) };
def tcost(t; r): ( numify(t.inputTokens) * r.in
                 + numify(t.outputTokens) * r.out
                 + numify(t.cacheWriteTokens) * (r.in * 1.25)
                 + numify(t.cacheReadTokens) * (r.in * 0.05) ) / 1000000;
({"opus":{"in":4,"out":20},"sonnet":{"in":2,"out":10}}) as $rates
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
  || fail "malformed input (unparseable JSON, missing/empty runId, or non-numeric token/wallClock) - no record written"

# --finalize only: attach the raw per-dispatch entries this mode's aggregation
# pass set aside, so the record carries a per-agent durationMs breakdown the
# summed wallClockSeconds above cannot give back on its own.
if [ -n "$finalize_agents" ]; then
  wrapper="$(printf '%s' "$wrapper" | jq --argjson agents "$finalize_agents" '.record.agents = $agents' 2>/dev/null)" \
    || fail "internal aggregation error attaching agents - no record written"
fi

# Sanitize runId for the FILENAME only (raw runId stays verbatim in the body):
# map every byte outside [A-Za-z0-9._-] to '-' (tr -c complements the set; printf
# adds no trailing byte, so no spurious trailing dash). Byte-wise under LC_ALL=C.
# `tr -d '\r'` strips the CR that jq's Windows build text-adds when it maps '\n' ->
# CRLF on stdout (a bare $(...) strips only trailing '\n', not '\r', so without this
# a normal runId could pick up a trailing '-' on a non-msys Windows bash).
# Parity scope: for realistic runIds (plain identifiers - the AC examples are
# "run-happy", "run/1 x") the sanitized filename is byte-identical to the pwsh
# UTF-8-byte twin. A runId containing a RAW CR/LF byte is pathological and NOT
# guaranteed filename-identical across twins (jq -r emits a data CR verbatim, which
# this tr also drops, whereas the pwsh byte loop maps it to '-'); it does not matter
# - filenames already differ by the unique nonce, and the record BODY (JSON mode,
# where jq escapes any CR as \r) stays byte-identical across both twins.
runId_raw="$(printf '%s' "$wrapper" | jq -r '.record.runId' | tr -d '\r')"
sanitized="$(printf '%s' "$runId_raw" | tr -c 'A-Za-z0-9._-' '-')"

# Filename: <sanitized>-<UTC-unix-seconds>-<nonce>.json. Nonce mirrors the
# existing per-run pattern at scripts/render-daemon.sh (TOKEN="rd-$$-$(date +%s)-$RANDOM"): $$-$(date +%s)-$RANDOM.
ts="$(date -u +%s)"
nonce="$$-$(date +%s)-$RANDOM"
dir=".milestone-config/.runtime/cost-records"
rel="$dir/${sanitized}-${ts}-${nonce}.json"

# Create the scratch dir. Mirrors the mkdir -p idiom in
# scripts/render-daemon.sh (write_state()), repeated there at the detached
# serverCmd spawn. Uncreatable /
# unwritable -> fail-open.
mkdir -p "$dir" 2>/dev/null || fail "cannot create $dir - no record written"

# Wrap the write in a group so the redirect's OWN open-failure (e.g. an existing
# read-only cost-records/ dir, where mkdir -p succeeds but `> "$rel"` cannot open)
# is swallowed by the group's 2>/dev/null instead of leaking a second bash
# diagnostic to real fd2 - exactly ONE fail-open line either way. The `tr -d '\r'`
# makes the record LF-only even where jq's Windows build text-maps '\n' -> CRLF on
# stdout (jq escapes any literal CR inside a string as \r, so only translated line-
# ending CRs are stripped, never record data) - byte-parity with the LF-forcing
# pwsh twin (write-cost-record.ps1 ConvertTo-Json normalization).
if ! { printf '%s' "$wrapper" | jq '.record' | tr -d '\r' > "$rel"; } 2>/dev/null; then
  fail "cannot write record to $rel - no record written"
fi

# Record is written - NOW emit one stderr note per unpriced tier. Emitting AFTER the
# write (not before) guarantees a write fail-open above stays a SINGLE stderr line,
# never note(s) + the fail line. `tr -d '\r'` drops jq's Windows CRLF so a tier name
# carries no stray CR; no empty-name guard, so a (pathological) empty-string tier key
# still yields exactly one note - parity with the pwsh foreach.
[ -z "$finalize_note" ] || printf 'write-cost-record: %s - using unsplit totals\n' "$finalize_note" >&2
while IFS= read -r t; do
  printf "write-cost-record: tier '%s' has no rate table entry - recorded under unpricedTiers, excluded from costUsd\n" "$t" >&2
done < <(printf '%s' "$wrapper" | jq -r '.unpriced[]' | tr -d '\r')

printf '%s\n' "$rel"
exit 0
