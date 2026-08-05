#!/usr/bin/env bash
# milestone-driver — dependency-free citation anchor resolver (issue #417).
# Usage: resolve-citation.sh <file-path> <anchor-text>
# Reports EVERY occurrence of <anchor-text> in <file-path>, one TAB-separated
# record per line, in FILE ORDER:
#   PRIMARY<TAB><line><TAB><text>   the FIRST occurrence in the file
#   MATCH<TAB><line><TAB><text>     every further occurrence
# <line> is 1-based. <text> is the ENTIRE matched line, VERBATIM — leading
# whitespace and any embedded literal TAB included — so a consumer splits on the
# FIRST TWO tabs only and takes the whole remainder as the text. Same TAB-record
# convention as scripts/parse-md-epic-order.sh:106 and
# scripts/check-skill-frontmatter.sh:128.
# Match rule: LITERAL SUBSTRING, CASE-SENSITIVE, exact bytes. NOT a regex — a
# '.' or '*' in the anchor matches only itself. Matching is LINE-SCOPED (the
# per-line scan loop mirrors scripts/read-doc-section.sh:46), so an anchor
# containing a real newline can never match: no single line holds one.
# PRIMARY is a LABEL, NOT A FILTER. A bare method-name anchor legitimately hits
# its declaration and its call sites, and every hit is reported, so a
# poorly-chosen anchor costs a scan rather than a wrong answer. The fix for a
# multi-match anchor is a better anchor at authoring time, not machinery here.
# First-occurrence-wins mirrors read-doc-section.sh:11; there is no hint-line
# argument and no nearest-match logic.
# One citation per invocation: no stdin, no batch mode — the caller loops.
#
# LINE MODEL — identical on both legs by construction, because a <line> that
# differs between the twins is the worst answer a citation resolver can give:
#   - Lines split on LF ONLY. A lone CR is ORDINARY TEXT, never a terminator:
#     it stays inside <text> and never shifts a line number. (The pwsh twin
#     reads -Raw and splits by hand for exactly this reason — Get-Content's
#     default line splitting ALSO breaks on a lone CR, which would report a
#     different line number than this leg for the same bytes.)
#   - A single trailing CR per line is stripped, so a CRLF working tree
#     (Windows core.autocrlf) yields the same <text> as an LF one. Mirrors
#     scripts/parse-md-epic-order.sh:47.
#   - A leading UTF-8 BOM on line 1 is stripped, so line-1 <text> matches the
#     pwsh twin's (whose reader consumes the BOM). Issue #418 points this at
#     arbitrary repo files, where a BOM is a real possibility.
# OUT OF CONTRACT: files containing NUL bytes. `read` DISCARDS NUL bytes from
#   the line while the pwsh twin keeps them, so <text> differs and the two legs
#   can return DIFFERENT EXIT CODES for the same binary input — measured: on a
#   line reading "before<NUL>after", the anchor "beforeafter" matches here
#   (exit 0) and not on the twin (exit 1). Binary files are not citation
#   targets; this divergence is documented, not aligned.
#
# Fail-loud (fail-CLOSED, mirrors read-doc-section.sh:12-16): a missing anchor,
#   a missing/unreadable file, or bad usage writes a clear message to stderr
#   (naming the anchor and/or the file) and exits NONZERO with NO stdout —
#   never silent empty output, and never a partial record set.
# Dependency-free: POSIX-ish bash + coreutils only — no yq/python/jq. Adding a
#   tool dependency is a STOP-and-ask gate, and this plugin's stated
#   non-negotiable is "no new tool dependency" — the same posture
#   check-size-budgets.sh and the CI-preflight parser take over their own narrow
#   surfaces (.project/library-manifest.md#Adding a dependency (the gate);
#   docs/architecture.md#preflight-optional).
# Exit codes: 0 at least one match · 1 missing/unreadable file, or anchor not
#   found · 2 bad usage — an argument count other than 2, or a present-but-EMPTY
#   anchor (an empty substring matches every line, so it is a usage error rather
#   than a whole-file answer; same exit code read-doc-section.sh:27 uses).
set -euo pipefail
# Byte-deterministic string model (mirrors read-doc-section.sh:21-23): keep the
# substring comparison byte-indexed so a multibyte anchor can't desync this leg
# from the pwsh UTF-16 twin.
export LC_ALL=C

err() { printf '%s\n' "$*" >&2; }

[ "$#" -eq 2 ] || { err "usage: resolve-citation.sh <file-path> <anchor-text>"; exit 2; }
file="$1"; anchor="$2"

[ -n "$anchor" ] || { err "resolve-citation: empty anchor-text: an empty anchor matches every line"; exit 2; }

[ -f "$file" ] && [ -r "$file" ] || { err "resolve-citation: file not found or not readable: $file"; exit 1; }

TAB=$'\t'
BOM=$'\xEF\xBB\xBF'
lineno=0
count=0
# Collect the records in an array and emit once at the end. Buffering is what
# makes the fail-CLOSED contract work (a miss must leave stdout empty), and an
# ARRAY rather than string concatenation is what keeps it O(n): concat-in-the-
# loop measured 0.21s at 2,000 matches but 22.1s at 20,000, against a 0.15s scan.
recs=()

while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno+1))
  # BOM applies to line 1 only — see LINE MODEL above.
  if [ "$lineno" -eq 1 ]; then line="${line#"$BOM"}"; fi
  line="${line%$'\r'}"
  # Literal substring test. Quoting "$anchor" inside the case pattern is what
  # makes it literal: an unquoted expansion would let a '*' or '[' in the
  # anchor act as a glob.
  case "$line" in
    *"$anchor"*) ;;
    *) continue ;;
  esac
  count=$((count+1))
  if [ "$count" -eq 1 ]; then kind=PRIMARY; else kind=MATCH; fi
  recs+=("$kind$TAB$lineno$TAB$line")
done < "$file"

if [ "$count" -eq 0 ]; then
  err "resolve-citation: anchor not found: '$anchor' in $file"
  exit 1
fi

# The count>0 check above is what makes this expansion safe under `set -u`:
# expanding an EMPTY array is an unbound-variable error on bash 3.2 (macOS).
printf '%s\n' "${recs[@]}"
