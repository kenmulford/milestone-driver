#!/usr/bin/env bash
# milestone-driver - CI table-of-contents gate (issue #490).
#
# Asserts that every governed `.md` file OVER 100 LINES carries `## Contents`
# as its FIRST level-2-or-higher heading. The standard being satisfied is
# platform.claude.com agent-skills/best-practices, "Structure longer reference
# files with table of contents": an agent that reads the head of a long
# reference file (`head -100`, or scripts/read-doc-section.sh on one anchor)
# stays blind to the file's remaining scope unless the top of the file names it.
#
# THIS SCRIPT ASSERTS THE HEADING AND ITS POSITION, NOTHING MORE. It does not
# read the index body, and it does not check that the entries under it match
# the file's actual headings. Those would need a markdown model this checker
# deliberately does not have.
#
# THE SCAN DOES NOT LOOK FOR AN H1, and anchoring it on one would be wrong
# twice over in this repo:
#   - agents/design-reviewer.md, agents/implementer.md and
#     agents/triage-reviewer.md carry NO `^# ` line at all. Every one of the
#     three opens on a level-2 heading, so an H1-anchored scan finds nothing to
#     position `## Contents` against.
#   - skills/setup/SKILL.md, skills/solve-milestone/trello-sync.md and
#     skills/solve-milestone/changelog-authoring.md each contain several `^# `
#     lines that are BASH COMMENTS INSIDE FENCED CODE BLOCKS. A dependency-free,
#     line-oriented scanner cannot tell those from a heading, so an H1-anchored
#     scan would anchor inside a fence.
# Requiring level 2 or higher sidesteps both: a level-1 line, fenced or not,
# is never the heading under test, and never displaces one either.
#
# The scan therefore is: skip a leading YAML frontmatter fence, then take the
# file's first line matching `^#{2,} ` and require it to be `## Contents`
# (level exactly 2, heading text exactly "Contents" after trimming). Anything
# ahead of it that is NOT such a heading - frontmatter, intro prose, an H1, a
# fenced block - does not violate the rule.
#
# FENCE CAVEAT, by design. Apart from the leading frontmatter fence the scan is
# line-oriented, exactly like scripts/read-doc-section.sh's ATX heading scan,
# which carries the same limitation on purpose. A heading-shaped line inside a
# fence placed BEFORE the file's real first heading would therefore be read as
# a heading. That shape does not occur in the governed set: every fenced
# pseudo-heading it holds sits in skills/solve-milestone/changelog-authoring.md
# - the CHANGELOG skeleton under that file's `## 6.5 Author the CHANGELOG
# entry` (whose `## v<target-version> - <milestone theme>` is the level-2 one)
# and the sample under its `## CHANGELOG preview`. Both sit far behind that
# file's `## Contents`, which is its first heading, and the scan stops at the
# first heading it finds. tests/fixtures/check-doc-toc/fenced-pseudo-heading/
# pins exactly that arrangement. DO NOT ADD GENERAL FENCE PARSING to widen it
# - that is a markdown model, and .project/library-manifest.md#Adding a
# dependency (the gate) is the reason this whole family of checkers has none.
#
# Threshold: STRICTLY OVER 100 lines. A file at or under 100 lines passes
# whether or not it carries the heading - a reader takes in a 100-line file
# whole, so an index buys it nothing. 100 exactly passes; 101 is measured.
#
# Usage:   check-doc-toc.sh [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# Output (stdout), one line per governed file plus a trailing summary,
# TAB-separated (mirrors check-size-budgets.sh's record stream):
#   OK      <path>
#   FAIL    <path>
#   FAIL    <path>  MISSING
#   SUMMARY ok=<N>  failed=<M>
# Exit 0 only when every listed file is present and compliant; exit 1 when any
# file is missing, or is over the threshold without `## Contents` first.
# Dependency-free (`wc -l` and shell builtins only) and bash-3.2-safe: no
# ${var,,}, no `declare -A`, no `mapfile`.
set -u
export LC_ALL=C

ROOT="${1:-$PWD}"
ROOT="${ROOT%/}"

# Lines strictly above this count make `## Contents` mandatory.
THRESHOLD=100

# The governed set, PATH ONLY - mirrored row for row from the path column of
# scripts/check-size-budgets.sh's GOVERNED_TABLE, which is this repo's one
# definition of "a governed file". No ceilings here: the two checkers govern
# the same files against different properties, and duplicating the ceilings
# would give them a second place to drift.
#
# KEEP THIS TABLE IN SYNC with GOVERNED_TABLE's path column and with
# scripts/check-doc-toc.ps1's $governedPaths, in the SAME change that adds,
# renames, or drops a governed file. A file that is renamed or deleted without
# the table following is a FAILURE here (FAIL … MISSING), not a silent pass -
# same posture as the size-budget ratchet.
#
# Rows start at column 0; `#` starts a comment row.
FILES=()
nfiles=0
# bash-3.2-safe: `read` and `case` builtins plus index assignment, no
# associative arrays and no `mapfile`; the heredoc feeds the loop in the
# CURRENT shell, so the array it fills survives it.
while read -r f; do
  case "$f" in ''|'#'*) continue ;; esac
  FILES[$nfiles]="$f"; nfiles=$((nfiles + 1))
done <<'GOVERNED_PATHS'
skills/setup/SKILL.md
skills/solve-issue/SKILL.md
skills/solve-issue/async-mode.md
skills/solve-issue/md-epic-fanout.md
skills/solve-issue/coherence-review.md
skills/solve-issue/milestone-clauses.md
skills/solve-issue/permission-preflight.md
skills/solve-issue/post-fix-commit.md
skills/solve-issue/preflight-github-ci.md
skills/solve-issue/resume-paths.md
skills/solve-issue/version-bump.md
skills/solve-issue/visual-capture.md
skills/solve-issue/wave-clauses.md
skills/solve-milestone/SKILL.md
skills/solve-milestone/parallel-waves.md
skills/solve-milestone/trello-sync.md
skills/solve-milestone/milestone-granularity.md
skills/solve-milestone/abandoned-recovery.md
skills/solve-milestone/blocked-label-clear.md
skills/solve-milestone/changelog-authoring.md
skills/solve-milestone/contingencies.md
skills/solve-milestone/db-hazard-interview.md
skills/solve-milestone/integration-granularity.md
skills/solve-milestone/md-epic-parent-check.md
skills/solve-milestone/not-buildable.md
skills/solve-milestone/sequential-loop.md
skills/solve-milestone/simplify-pass.md
skills/solve-milestone/version-target.md
skills/triage/SKILL.md
skills/triage/blocker-resolver-dispatch.md
skills/notices.md
skills/output-style.md
skills/citation-format.md
skills/remediate-handoff.md
agents/blocker-resolver.md
agents/design-reviewer.md
agents/implementer.md
agents/triage-reviewer.md
GOVERNED_PATHS

ok=0
failed=0
i=0
# Index loop, not a `while read` over the table: the inner scan below redirects
# stdin from the file under test, and an index loop has no stdin of its own to
# lose. Mirrors check-size-budgets.sh.
while [ "$i" -lt "$nfiles" ]; do
  f="${FILES[$i]}"
  path="$ROOT/$f"
  i=$((i + 1))

  if [ ! -f "$path" ]; then
    printf 'FAIL\t%s\tMISSING\n' "$f"
    failed=$((failed + 1))
    continue
  fi

  # `wc -l` counts newlines, so a final line with no trailing newline is not
  # counted - the pwsh twin counts 0x0A bytes to match exactly, and both are
  # CRLF-proof.
  lines="$(wc -l < "$path")"
  lines="${lines//[[:space:]]/}"
  if [ "$lines" -le "$THRESHOLD" ]; then
    printf 'OK\t%s\n' "$f"
    ok=$((ok + 1))
    continue
  fi

  lineno=0
  in_frontmatter=0
  level=0
  text=""
  found=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # Tolerate a CRLF working tree even though .gitattributes pins *.md and
    # tests/fixtures/** to LF; an unstripped CR would leave the heading text
    # "Contents\r" and fail a compliant file.
    line="${line%$'\r'}"

    # Skip a LEADING YAML frontmatter fence only: `---` on line 1 opens it, the
    # next `---` closes it. Every skill and agent file in the governed set
    # opens with one, and a `## Contents` inside frontmatter would not be a
    # heading at all.
    if [ "$lineno" -eq 1 ] && [ "$line" = "---" ]; then in_frontmatter=1; continue; fi
    if [ "$in_frontmatter" -eq 1 ]; then
      if [ "$line" = "---" ]; then in_frontmatter=0; fi
      continue
    fi

    # Level 2 or higher only. A `# ...` line - an H1, or a bash comment inside
    # a fence, which this scanner cannot tell apart - is ordinary content.
    case "$line" in
      '##'*) ;;
      *) continue ;;
    esac
    rest="$line"
    level=0
    while [ "${rest#'#'}" != "$rest" ]; do level=$((level + 1)); rest="${rest#'#'}"; done
    # ATX requires a space after the #s. A bare `##` or a `##hashtag` is body
    # text, matching scripts/read-doc-section.sh's heading rule.
    case "$rest" in
      ' '*) ;;
      *) level=0; continue ;;
    esac
    # Trim surrounding whitespace off the heading text, same normalization
    # read-doc-section.sh applies before comparing an anchor - so a heading
    # this gate accepts is one `read-doc-section.sh <doc> Contents` can reach.
    text="${rest#"${rest%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    found=1
    break
  done < "$path"

  if [ "$found" -eq 1 ] && [ "$level" -eq 2 ] && [ "$text" = "Contents" ]; then
    printf 'OK\t%s\n' "$f"
    ok=$((ok + 1))
  else
    printf 'FAIL\t%s\n' "$f"
    failed=$((failed + 1))
  fi
done

printf 'SUMMARY\tok=%s\tfailed=%s\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
