#!/usr/bin/env bash
# milestone-driver - process-check status and record (issue #791).
# Usage: process-check.sh --status <repo-root>
#        process-check.sh --record <clean|updated|declined> <repo-root>
# --status prints `due` or `current`. --record prints nothing. The marker is
# <repo-root>/.milestone-config/.runtime/process-check.json, one line
# {"hash":"<digest>","outcome":"<outcome>"} plus LF; --status compares only hash.
# The digest is `git hash-object --stdin` over LF-terminated manifest lines:
# `contract <blob>` first, then `<blob> <repo-relative path>` per present scanned
# file in byte order. Each <blob> is `git hash-object --no-filters`, so line-ending
# filters never change it. The contract is skills/process-check.md in this
# script's own plugin install, since the invocation carries no plugin-root argument.
# Scanned files: CLAUDE.md, AGENTS.md and .claude/CLAUDE.md at the repo root, the
# *.md directly inside .project/ and inside the profile's projectDocs directory
# (default .project/), and each standingDocs entry's <doc> part under projectDocs.
# An absent scanned file is skipped; an absent driver.json resolves to the defaults.
# The marker is built in a temp file beside it and moved into place, so a failed
# write leaves the old marker. A marker that is not one JSON object with a string
# hash reads as `due`. Check order: usage, jq, driver.json, contract.
# The .ps1 twin parses with ConvertFrom-Json, so its jq line never occurs.
# Exit codes: 0 ok · 1 jq absent / unreadable profile or contract / write failure · 2 bad usage.
set -u

err() { printf 'process-check: %s\n' "$*" >&2; }
usage() { err 'usage: process-check (--status | --record <clean|updated|declined>) <repo-root>'; exit 2; }
die() { err "$1"; exit 1; }

outcome=""
case "${1:-}" in
  --status) [ "$#" -eq 2 ] || usage; root="$2" ;;
  --record)
    [ "$#" -eq 3 ] || usage
    outcome="$2"; root="$3"
    case "$outcome" in clean|updated|declined) ;; *) usage ;; esac ;;
  *) usage ;;
esac
[ -n "$root" ] && [ -d "$root" ] || usage
mode="$1"
command -v jq >/dev/null 2>&1 || die 'jq is required but not on PATH'

here="$(cd "$(dirname "$0")" && pwd)"
plugin="$(dirname "$here")"
profile="$root/.milestone-config/driver.json"

pd=""; docs=""
if [ -e "$profile" ]; then
  parsed="$([ -f "$profile" ] && jq -rs 'if length == 1 and (.[0] | type) == "object" then .[0] | ((.projectDocs | strings) // ""), (.standingDocs | arrays | .[] | strings | split("#")[0]) else error("not one object") end' "$profile" 2>/dev/null)" \
    || die 'cannot read .milestone-config/driver.json'
  parsed="${parsed//$'\r'/}"
  pd="${parsed%%$'\n'*}"
  case "$parsed" in *$'\n'*) docs="${parsed#*$'\n'}" ;; esac
fi
while [ "${pd#./}" != "$pd" ]; do pd="${pd#./}"; done
while [ "${pd%/}" != "$pd" ]; do pd="${pd%/}"; done
[ -n "$pd" ] || pd='.project'

contract="$plugin/skills/process-check.md"
c=""
if [ -f "$contract" ] && [ -r "$contract" ]; then c="$(git hash-object --no-filters -- "$contract" 2>/dev/null)"; fi
[ -n "$c" ] || die 'cannot read skills/process-check.md'

list=$'CLAUDE.md\nAGENTS.md\n.claude/CLAUDE.md\n'
for d in .project "$pd"; do
  for f in "$root/$d"/*.md; do
    [ -f "$f" ] && list="$list$d/${f##*/}"$'\n'
  done
done
while IFS= read -r doc; do
  while [ "${doc#./}" != "$doc" ]; do doc="${doc#./}"; done
  [ -n "$doc" ] && list="$list$pd/$doc"$'\n'
done <<< "$docs"

manifest="contract $c"$'\n'
while IFS= read -r rel; do
  [ -n "$rel" ] && [ -f "$root/$rel" ] || continue
  h="$(git hash-object --no-filters -- "$root/$rel" 2>/dev/null)" || continue
  manifest="$manifest$h $rel"$'\n'
done <<< "$(printf '%s' "$list" | LC_ALL=C sort -u)"
digest="$(printf '%s' "$manifest" | git hash-object --stdin 2>/dev/null)"
[ -n "$digest" ] || die 'cannot read skills/process-check.md'

rt="$root/.milestone-config/.runtime"
marker="$rt/process-check.json"

if [ "$mode" = "--status" ]; then
  res=""
  [ -f "$marker" ] && res="$(jq -rs --arg d "$digest" 'if length == 1 and (.[0] | type) == "object" and (.[0].hash | type) == "string" and .[0].hash == $d then "current" else "due" end' "$marker" 2>/dev/null)"
  res="${res//$'\r'/}"
  if [ "$res" = "current" ]; then printf 'current\n'; else printf 'due\n'; fi
  exit 0
fi

tmp="$marker.tmp.$$"
wfail() { rm -f "$tmp" 2>/dev/null; die 'cannot write .milestone-config/.runtime/process-check.json'; }
mkdir -p "$rt" 2>/dev/null || wfail
[ -d "$marker" ] && wfail
{ printf '{"hash":"%s","outcome":"%s"}\n' "$digest" "$outcome" > "$tmp"; } 2>/dev/null || wfail
mv -f "$tmp" "$marker" 2>/dev/null || wfail
exit 0
