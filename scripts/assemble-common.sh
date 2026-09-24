#!/usr/bin/env bash
# milestone-driver - assemble one common.md from the prose contract and standing anchors (issue #692).
# Usage: assemble-common.sh <repo-root> <out-file> [<doc>#<heading> ...]
# Writes <out-file> holding, in order: the four skills/output-style.md sections
# the implementer brief names, skills/citation-format.md whole, then each
# <doc>#<heading> argument's section via read-doc-section. Parts are separated by
# exactly one blank line, so each part's trailing newlines are dropped first.
# An argument splits on its FIRST '#'. <doc> is joined onto <repo-root>, never
# resolved against the cwd. The contract files are read from this script's own
# plugin install, since the signature carries no plugin-root argument.
# Fail-CLOSED and atomic: the file is built in a temp file beside <out-file> and
# moved into place only on success, so any failure leaves <out-file> as it was.
# Exit codes: 0 ok · 1 missing file / missing anchor / write failure · 2 bad usage.
set -u

err() { printf '%s\n' "$*" >&2; }

[ "$#" -ge 2 ] || { err "usage: assemble-common.sh <repo-root> <out-file> [<doc>#<heading> ...]"; exit 2; }
root="$1"; out="$2"; shift 2
for a in "$@"; do
  case "$a" in
    *'#'*) ;;
    *) err "assemble-common: anchor argument has no '#': $a"; exit 2 ;;
  esac
done

here="$(cd "$(dirname "$0")" && pwd)"
plugin="$(dirname "$here")"

body=""
add() { if [ -z "$body" ]; then body="$1"; else body="$body

$1"; fi; }
# "$BASH" keeps the child on this interpreter (the macOS /bin/bash 3.2 CI venue).
section() { local s; s="$("$BASH" "$here/read-doc-section.sh" "$1" "$2")" || return 1; add "$s"; }

for h in 'GitHub-facing prose' 'When prose is the correct form' 'Evidence slots' 'The two anti-criteria'; do
  section "$plugin/skills/output-style.md" "$h" || exit 1
done
cite="$(cat "$plugin/skills/citation-format.md")" || { err "assemble-common: cannot read $plugin/skills/citation-format.md"; exit 1; }
add "$cite"
for a in "$@"; do
  doc="${a%%'#'*}"; heading="${a#*'#'}"
  section "$root/$doc" "$heading" || { err "assemble-common: cannot resolve anchor '$a' in $root/$doc"; exit 1; }
done

tmp="$out.tmp.$$"
if ! { printf '%s\n' "$body" > "$tmp"; } 2>/dev/null || ! mv -f "$tmp" "$out" 2>/dev/null; then
  rm -f "$tmp" 2>/dev/null
  err "assemble-common: cannot write $out"
  exit 1
fi
