#!/usr/bin/env bash
# milestone-driver — deterministic md-epic-order block parser (issue #266).
# stdin: a parent issue's raw body text. stdout (success): one TAB-separated
# record per block entry, in block order — "<kind><TAB><raw>" (kind = number|
# title). An empty block (zero non-blank interior lines) is success with empty
# stdout. stderr is used ONLY on failure, naming the failure; exit 0 on any
# success (including the empty-block case), exit 1 on any failure.
#
# Scope boundary: this script ONLY locates and structurally validates the
# ```md-epic-order fenced block. It never calls `gh`, never touches the
# network, and never resolves an entry to a real milestone — that lookup is
# deferred to skill prose (a sibling issue), per the design spec's U2 interface
# (docs/superpowers/specs/2026-07-04-md-epic-driver-fanout-design.md, "The
# ordered milestone list block" / U2).
#
# Block location: scan top-to-bottom for a line exactly "```md-epic-order";
# first match wins on duplicate blocks (mirrors scripts/read-doc-section.sh's
# first-occurrence policy). The block ends at the next line that is exactly
# "```"; EOF before that is an unterminated-fence failure.
# Grammar (interior, blank/whitespace-only lines ignored, never counted as
# entries): each non-blank line matches EXACTLY "number: <integer>" or
# "title: <text>", case-sensitive. <integer> = ^(0|[1-9][0-9]*)$ (mirrors
# scripts/extract-version.sh:28). Any other non-blank line invalidates the
# WHOLE block — parsing stops at the first malformed line.
# Fail-loud/fail-closed exit convention (mirrors scripts/read-doc-section.sh:11-19).
set -u
# Byte-deterministic string model (mirrors extract-version.sh / read-doc-section.sh):
# exact-match comparisons and prefix stripping stay byte-indexed so a multibyte
# line can't desync this bash leg from the pwsh UTF-16 twin.
export LC_ALL=C

OPEN_FENCE='```md-epic-order'
CLOSE_FENCE='```'

err() { printf '%s\n' "$*" >&2; }

state=search   # search | inside
found_open=0
closed=0
open_line=0
pos=0
declare -a kinds=()
declare -a raws=()
lineno=0

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"   # tolerate CRLF bodies (mirrors ci-preflight-steps.sh)
  lineno=$((lineno+1))

  if [ "$state" = "search" ]; then
    if [ "$line" = "$OPEN_FENCE" ]; then
      state=inside
      found_open=1
      open_line="$lineno"
    fi
    continue
  fi

  # state=inside — position is 1-based from the first line inside the block,
  # blank lines included in the count.
  pos=$((pos+1))

  if [ "$line" = "$CLOSE_FENCE" ]; then
    closed=1
    break
  fi

  # blank/whitespace-only interior line: ignored (never malformed, never counted
  # as an entry). Trim idiom mirrors scripts/read-doc-section.sh:66-67.
  trimmed="${line#"${line%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [ -z "$trimmed" ] && continue

  case "$line" in
    number:\ *)
      val="${line#number: }"
      if [[ "$val" =~ ^(0|[1-9][0-9]*)$ ]]; then
        kinds+=("number"); raws+=("$val")
        continue
      fi
      ;;
    title:\ *)
      val="${line#title: }"
      if [ -n "$val" ]; then
        kinds+=("title"); raws+=("$val")
        continue
      fi
      ;;
  esac

  err "parse-md-epic-order: malformed line at position $pos: '$line'"
  exit 1
done

if [ "$found_open" -eq 0 ]; then
  err "parse-md-epic-order: no md-epic-order block found"
  exit 1
fi

if [ "$closed" -eq 0 ]; then
  err "parse-md-epic-order: unterminated md-epic-order fence opened at line $open_line"
  exit 1
fi

for i in "${!kinds[@]}"; do
  printf '%s\t%s\n' "${kinds[$i]}" "${raws[$i]}"
done
exit 0
