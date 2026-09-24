#!/usr/bin/env bash
# milestone-driver - dispatch step and first-edit metrics from one subagent
# JSONL transcript (issue #693).
# Usage: measure-dispatch.sh <transcript>
# stdout: ONE compact JSON line, keys in order
#   {"steps":n,"stepsBeforeFirstEdit":n,"minutesToFirstEdit":m,"minutes":m}
#   With no edit call, only {"steps":n,"minutes":m}. No transcript text ever
#   reaches stdout.
# Transcript shape: one JSON object per line; a top-level "timestamp" (ISO-8601
#   UTC); a tool call is a message.content[] block {"type":"tool_use","name":...}
#   on an entry whose top-level "type" is "assistant". Lines that are not JSON
#   objects are skipped.
# Timestamps are truncated to whole seconds (jq's fromdate rejects fractional
#   seconds; GNU `date -d` is not portable), so the pwsh twin truncates too and the
#   legs agree. Minutes round to one decimal, half away from zero (jq's round),
#   and a whole value prints without a decimal point.
# The first-edit time is the latest timestamp seen at or before the entry holding
#   the first Edit, Write, or file-writing Bash call. A Bash call writes a file
#   when its input.command contains `sed -i` or `perl -i`, a word `tee ` not
#   followed by `/dev/null`, or a `>`/`>>` redirect whose target is neither
#   `/dev/null` nor an fd (`&1`, `&2`). Substring and regex checks only, no shell
#   parsing, so a `>` inside a quoted string also counts. The pwsh twin uses the
#   same two regexes; Oniguruma and .NET agree on them (no POSIX classes).
# Fail-closed, mirroring scripts/read-doc-section.sh (Fail-loud (fail-CLOSED)):
#   a missing/unreadable file or absent jq writes one stderr line, exits NONZERO,
#   and prints nothing on stdout.
# Exit codes: 0 ok · 1 unreadable file / jq absent / timestamp parse failure · 2 bad usage.
set -euo pipefail

err() { printf '%s\n' "$*" >&2; }

[ "$#" -eq 1 ] || { err "usage: measure-dispatch.sh <transcript>"; exit 2; }
file="$1"

[ -f "$file" ] && [ -r "$file" ] || { err "measure-dispatch: file not found or not readable: $file"; exit 1; }
command -v jq >/dev/null 2>&1 || { err "measure-dispatch: jq is required but not on PATH"; exit 1; }

PROG='
def secs: sub("\\.[0-9]+"; "") | fromdate;
def mins($a; $b): if $a == null or $b == null then 0 else ((($b - $a) / 6) | round) / 10 end;
def bashedit: ((.input | objects | .command | strings) // "")
  | contains("sed -i") or contains("perl -i")
    or test("(^|[^A-Za-z0-9_-])tee[ \t]+(?!/dev/null)")
    or test(">>?[ \t]*(?!/dev/null)[^ \t>&]");
def isedit: .name == "Edit" or .name == "Write" or (.name == "Bash" and bashedit);
reduce (inputs | fromjson? | objects) as $e (
  {steps: 0, before: null, t0: null, tl: null, tf: null};
  (if ($e.timestamp | type) == "string" then ($e.timestamp | secs) else null end) as $t
  | (if $t != null then (.t0 //= $t | .tl = $t) else . end)
  | if $e.type == "assistant" then
      reduce (($e.message | objects | .content | arrays) // [] | .[] | objects
              | select(.type == "tool_use")) as $b (.;
        (if .before == null and ($b | isedit)
         then .before = .steps | .tf = .tl else . end)
        | .steps += 1)
    else . end)
| if .before == null then {steps, minutes: mins(.t0; .tl)}
  else {steps, stepsBeforeFirstEdit: .before, minutesToFirstEdit: mins(.t0; .tf), minutes: mins(.t0; .tl)}
  end'

# jq's Windows build text-maps its "\n" to CRLF; tr keeps the line LF-only.
out="$(jq -R -n -c "$PROG" "$file" 2>/dev/null | tr -d '\r')" \
  || { err "measure-dispatch: could not parse timestamps in: $file"; exit 1; }
printf '%s\n' "$out"
