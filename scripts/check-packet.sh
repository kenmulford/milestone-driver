#!/usr/bin/env bash
# milestone-driver - mechanical build-packet approval (issue #722).
# Usage: check-packet.sh <packet> <worktree> [light]
# Checks the packet skills/solve-issue/build-packet.md defines, reading only the
# lines outside fenced blocks: a packet is mostly byte-exact quotes, and a quoted
# markdown file carries `## ` and `### x (y)` lines that are not the packet's own.
# A line starting with three backticks toggles the fence.
#   header    the Issue:, Base: and Worktree: lines are present
#   base      Base: equals `git -C <worktree> rev-parse HEAD`
#   worktree  Worktree: equals <worktree>, one trailing '/' stripped from each
#   section   each required `## ` section is present; `## Tests` is optional
#             under `light`, `## Design` always is
#   citation  each `### <path> (<anchor>)` line, <path> holding no space,
#             resolves through resolve-citation.sh against <worktree>/<path>;
#             the anchor `new` marks a file absent at Base and is skipped
# Output: one FAIL<TAB><check><TAB><detail> line per failure, in the order above,
# then SUMMARY<TAB>ok=<n><TAB>failed=<m>. Same TAB-record convention as
# scripts/resolve-citation.sh (Reports EVERY occurrence).
# Line model as resolve-citation.sh: LF splits lines, one trailing CR is
# stripped, a line-1 UTF-8 BOM is stripped.
# Exit codes: 0 failed=0 · 1 any failure · 2 bad usage, an unreadable packet, or
# a worktree that is not a directory.
set -u
export LC_ALL=C

err() { printf '%s\n' "$*" >&2; }
usage="usage: check-packet.sh <packet> <worktree> [light]"

[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || { err "$usage"; exit 2; }
packet="$1"; wt="${2%/}"; light=0
if [ "$#" -eq 3 ]; then
  [ "$3" = light ] || { err "$usage"; exit 2; }
  light=1
fi
[ -f "$packet" ] && [ -r "$packet" ] || { err "check-packet: packet not found or not readable: $packet"; exit 2; }
[ -d "$wt" ] || { err "check-packet: worktree is not a directory: $wt"; exit 2; }

here="$(cd "$(dirname "$0")" && pwd)"
TAB=$'\t'
BOM=$'\xEF\xBB\xBF'
ok=0; failed=0
fails=()
pass() { ok=$((ok + 1)); }
fail() { failed=$((failed + 1)); fails+=("FAIL$TAB$1$TAB$2"); }

issue=0; base=''; hasbase=0; tree=''; hastree=0
sections="$TAB"
cites=()
lineno=0; fence=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  if [ "$lineno" -eq 1 ]; then line="${line#"$BOM"}"; fi
  line="${line%$'\r'}"
  case "$line" in
    '```'*) fence=$((1 - fence)); continue ;;
  esac
  [ "$fence" -eq 0 ] || continue
  case "$line" in
    'Issue: '*) issue=1 ;;
    'Base: '*) [ "$hasbase" -eq 1 ] || { hasbase=1; base="${line#Base: }"; } ;;
    'Worktree: '*) [ "$hastree" -eq 1 ] || { hastree=1; tree="${line#Worktree: }"; } ;;
    '## '*) sections="$sections${line#'## '}$TAB" ;;
    '### '*' ('*')')
      rest="${line#'### '}"; path="${rest%% *}"; tail="${rest#"$path"}"
      case "$tail" in
        ' ('*')') anchor="${tail#' ('}"; anchor="${anchor%')'}"
          [ -n "$path" ] && [ -n "$anchor" ] && cites+=("$path$TAB$anchor") ;;
      esac ;;
  esac
done < "$packet"

for h in Issue Base Worktree; do
  case "$h" in
    Issue) have=$issue ;;
    Base) have=$hasbase ;;
    Worktree) have=$hastree ;;
  esac
  if [ "$have" -eq 1 ]; then pass; else fail header "missing $h: line"; fi
done

if [ "$hasbase" -eq 1 ]; then
  headsha="$(git -C "$wt" rev-parse HEAD 2>/dev/null)" || headsha=unknown
  [ -n "$headsha" ] || headsha=unknown
  if [ "$base" = "$headsha" ]; then pass; else fail base "Base: $base != HEAD $headsha"; fi
fi
if [ "$hastree" -eq 1 ]; then
  if [ "${tree%/}" = "$wt" ]; then pass; else fail worktree "Worktree: $tree != $wt"; fi
fi

for s in 'Files' 'Edit points' 'Calls' 'Tests' 'Rules' 'Verified facts' 'Decisions' 'Verify' 'Out of scope'; do
  if [ "$s" = Tests ] && [ "$light" -eq 1 ]; then continue; fi
  case "$sections" in
    *"$TAB$s$TAB"*) pass ;;
    *) fail section "missing ## $s" ;;
  esac
done

# `${cites[@]}` on an empty array is an unbound-variable error under `set -u`
# on bash 3.2 (macOS), hence the count guard.
if [ "${#cites[@]}" -gt 0 ]; then
  for c in "${cites[@]}"; do
    path="${c%%"$TAB"*}"; anchor="${c#*"$TAB"}"
    [ "$anchor" = new ] && continue
    # "$BASH" keeps the child on this interpreter (the macOS /bin/bash 3.2 CI venue).
    if msg="$("$BASH" "$here/resolve-citation.sh" "$wt/$path" "$anchor" 2>&1 >/dev/null)"; then
      pass
    else
      fail citation "$path ($anchor): $msg"
    fi
  done
fi

if [ "${#fails[@]}" -gt 0 ]; then printf '%s\n' "${fails[@]}"; fi
printf 'SUMMARY\tok=%s\tfailed=%s\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
