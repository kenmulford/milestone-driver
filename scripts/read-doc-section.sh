#!/usr/bin/env bash
# milestone-driver — dependency-free anchored Markdown section reader (issue #184).
# Usage: read-doc-section.sh <doc-path> <anchor-text>
#   <anchor-text> is the heading text WITHOUT the leading #s (e.g. "Keys" matches
#   "## Keys"). Match rule: trim the leading #s and surrounding whitespace from a
#   heading line, compare the remainder to <anchor-text> CASE-SENSITIVE, exactly.
# Prints ONLY that section: the matched heading line through the line BEFORE the
# next heading whose level (count of leading #s) is <= the matched heading's
# level. If the matched heading is the last such section, prints through EOF.
# The matched heading line itself is included.
# Duplicate anchors (same heading text twice): match the FIRST occurrence.
# Fail-loud (fail-CLOSED): a missing/renamed anchor or a missing/unreadable file
#   writes a clear message to stderr (naming the anchor + file) and exits NONZERO
#   with NO stdout — never silent empty output. (This is an INTENTIONAL divergence
#   from extract-version.sh, which fails OPEN on a version miss; silent empty
#   grounding is the drift this seam exists to surface.)
# Dependency-free: POSIX-ish bash + coreutils only — no yq/python/jq.
# (docs/profile-schema.md:123 forbids new tool deps.)
# Exit codes: 0 ok · 1 missing file / missing anchor · 2 bad usage.
set -euo pipefail
# Byte-deterministic string model (mirrors extract-version.sh): keep boundary
# math byte-indexed so a multibyte heading can't desync vs the pwsh UTF-16 twin.
export LC_ALL=C

err() { printf '%s\n' "$*" >&2; }

[ "$#" -eq 2 ] || { err "usage: read-doc-section.sh <doc-path> <anchor-text>"; exit 2; }
doc="$1"; anchor="$2"

[ -f "$doc" ] && [ -r "$doc" ] || { err "read-doc-section: file not found or not readable: $doc"; exit 1; }

# heading_level <line> -> count of leading '#'s IF the line is an ATX heading
#   (one-or-more '#' followed by a space or end-of-line), else 0.
# heading_text <line> -> the text after the leading #s, surrounding whitespace
#   trimmed. Only called on lines already confirmed as headings.
# We scan line-by-line (mirrors extract-version.sh's scan loop) tracking whether
# we are inside the matched section and what level boundary closes it.

matched_level=0
in_section=0
found=0
# Accumulate the section body; print only after a successful match so a miss
# leaves stdout empty (fail-CLOSED contract).
out=""

while IFS= read -r line || [ -n "$line" ]; do
  # Is this an ATX heading? Leading #s then a space, or a bare line of only #s.
  level=0
  case "$line" in
    '#'*)
      # Count leading '#'s.
      rest="$line"
      while [ "${rest#'#'}" != "$rest" ]; do level=$((level+1)); rest="${rest#'#'}"; done
      # ATX requires a space (or EOL) after the #s; otherwise it's not a heading
      # (e.g. "#hashtag"), so treat as body.
      case "$rest" in
        '') : ;;                       # bare "###" — a heading with empty text
        ' '*) : ;;                     # "## Keys" — standard ATX heading
        *) level=0 ;;                  # "#hashtag" — not a heading
      esac
      ;;
  esac

  if [ "$level" -gt 0 ]; then
    # Trim leading whitespace from the post-# text, then trailing whitespace.
    text="${rest#"${rest%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    if [ "$in_section" -eq 1 ] && [ "$level" -le "$matched_level" ]; then
      # A heading at equal-or-higher level closes the section.
      break
    fi
    if [ "$found" -eq 0 ] && [ "$in_section" -eq 0 ] && [ "$text" = "$anchor" ]; then
      # First matching heading — open the section (first-match policy).
      found=1
      in_section=1
      matched_level="$level"
      out="$line"
      continue
    fi
  fi

  if [ "$in_section" -eq 1 ]; then
    out="$out
$line"
  fi
done < "$doc"

if [ "$found" -eq 0 ]; then
  err "read-doc-section: anchor not found: '$anchor' in $doc"
  exit 1
fi

printf '%s\n' "$out"
