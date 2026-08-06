#!/usr/bin/env bash
# milestone-driver — repo-wide citation gate (issue #432).
#
# Walks a checked-out repo, finds every citation this repo writes, and RESOLVES
# the one form that can be resolved — `path (anchor)`, per
# skills/citation-format.md (D1 — the `path (anchor)` form). An anchor that
# matches zero lines, or more than one, fails the run.
#
# Why the gate exists: an anchor points at a literal string, so any edit to that
# string breaks the citation SILENTLY — it still looks well-formed and still
# sends its reader somewhere. scripts/resolve-citation.sh resolves ONE citation
# per invocation and had no repo-walking caller. This is that caller.
#
# Usage:   check-citations.sh [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# Output (stdout), TAB-separated, mirroring scripts/check-size-budgets.sh's
# record-stream-then-summary shape:
#   EXCLUDED    <pattern>       skipped=<N>
#   OK          <file>:<line>   <citation>
#   FAIL        <file>:<line>   <citation>   <N> matches
#   UNVERIFIED  <file>:<line>   <citation>   <form> — not verified
#   TOTALS      unverified=<U>  excluded-files=<E>
#   SUMMARY     ok=<N>          failed=<M>
# EXCLUDED records come first, then citation records in byte-sorted file order,
# then line order, then left-to-right within a line. Exit 0 when failed=0,
# exit 1 otherwise.
#
# ── WHAT A GREEN RUN DOES NOT VERIFY ──────────────────────────────────────────
# A GREEN RUN VERIFIES ONLY `path (anchor)` CITATIONS. The other three forms in
# skills/citation-format.md (The four forms) are COUNTED AND REPORTED, NEVER
# RESOLVED, each as an UNVERIFIED record:
#   `path:line` / `path:start-end`  A line number is not checkable without an
#     author-supplied expected token, which this repo does not carry. Reporting
#     one and calling the run green would be the false assurance issue #407
#     warned about.
#   `path#Heading` / `path § Heading`  Resolvable in principle by
#     scripts/read-doc-section.sh, but NOT resolved here. Measured on a clean
#     tree, a heading matcher wired into this walk produced 23 FAIL records
#     against 23 CORRECT citations: 13 GitHub-slug headings (`#the-mechanical-
#     gates` against a real `## The mechanical gates`), 8 markdown link targets
#     that are not citations at all, and 2 headings holding backticks that a
#     backtick-delimited token cannot bound. A gate that fails on correct input
#     is worse than no gate, so the heading forms are reported and left
#     unresolved until a slug matcher exists.
# So `failed=0` means "every anchor still points at its string", NOT "every
# citation in this repo is good".
#
# ── WHAT COUNTS AS A CITATION (the discriminator) ─────────────────────────────
# skills/citation-format.md (What marks it as a citation) makes the code span
# the discriminator: a citation is one whole backtick-wrapped token. That rule
# is expressed here POSITIONALLY, which needs no backtick tracking and no
# markdown parser:
#
#   1. A PATH-CLASS RUN. The path is a maximal run of [A-Za-z0-9._/-]. Every
#      other byte — backtick, space, quote, `<`, `>`, `$`, `{` — ends the run,
#      and the citation form is decided by the bytes that FOLLOW it. This is
#      what kills the prose lookalikes the format file names: in
#      `` `agents/triage-reviewer.md` (architect lens) `` a CLOSING BACKTICK
#      sits where the citation's space would be, so what follows the path is not
#      ` (` and the phrase is prose. Same for `` `skills/setup/SKILL.md`
#      (Phase 2) ``, `` `.claude/settings.json` (project) `` and
#      `` `package.json` (generic Node) ``. No special-casing.
#   2. THE RUN MUST CONTAIN `/`. Measured: removes 24 further prose lookalikes
#      at ZERO cost to a real citation. The dominant class is this repo's own
#      test-runner header line, 18 of them, shaped `# milestone-driver —
#      golden-matrix runner for build-file-index.ps1 (issue #318).`
#   3. THE RUN MUST NOT START WITH `/`, and must end in an extension of 1–4
#      alphanumeric bytes holding at least one letter. Rule 1 already cuts
#      `<repo>` off `<repo>/.milestone-config/driver.json (…)`, leaving a run
#      that starts with `/`; the extension test drops version shapes like
#      `1.2 (…)` and bare prose like `Fail-loud (fail-CLOSED)`.
#   4. THE ANCHOR IS BOUNDED BY PAREN BALANCE, not by the final `)` on the line.
#      This is what recovers the nested anchors this repo really writes —
#      scripts/read-doc-section.sh (Fail-loud (fail-CLOSED)),
#      scripts/build-file-index.sh (extract_symbols() {),
#      scripts/read-doc-section.ps1 (if ($args.Count -ne 2) {) — and what drops
#      a prose parenthetical that runs off the end of the line without closing
#      (4 of them live, e.g. `.gitignore`'s wrapped settings comment).
# Measured against this repo on a clean tree: 168 anchor citations, all 168
# resolving to exactly one line.
#
# THE POSITION TEST IS NOT APPLIED. skills/citation-format.md also requires a
# citation to stand in a citation position (an evidence slot, or a grounding
# reference). That is a model judgment, not a mechanical one — see
# skills/solve-issue/SKILL.md (never a regex). This script deliberately runs the
# SPAN test only, and the four rules above are calibrated so that on this tree
# the span test alone has no false positives.
#
# ── EDGE CASES, AND THE CHOICE MADE FOR EACH ──────────────────────────────────
#   Prose that looks like a citation  Dropped by rules 1-4. NOT reported: a
#     prose parenthetical is not a citation and never was.
#   Heading ending in a parenthetical  A heading citation splits on the
#     SEPARATOR, never the parenthesis: the path-class run ends at `#`, so the
#     classifier sees the heading form and never reaches the ` (`. Reported
#     UNVERIFIED. The live example is library-manifest's "Adding a dependency
#     (the gate)" heading, cited seven times.
#   `${CLAUDE_PLUGIN_ROOT}/` paths  `$`, `{` and `}` are not path-class, so the
#     run starts at the `/` after `}` and is dropped by rule 3 (leading `/`).
#     Never reported as missing. None is written in the anchor form today; if
#     one ever is, it goes UNREPORTED rather than failing.
#   Cross-repo citations  Not distinguishable from a local path by shape. Every
#     live one is a LINE form — `skills/output-style.md` cites milestone-feeder's
#     `agents/issue-author.md` by line range — so every live one lands in
#     UNVERIFIED and cannot fail the build. A cross-repo ANCHOR citation WOULD
#     fail as `0 matches`; none exists, and citation-format.md's repo-root base
#     rule is why one should not be written.
#   Bare `:NNN` continuations  A token with no path before the colon has no
#     path-class run, so it is never picked up — skipped by construction. It
#     carries no path to check.
#   Same-file citations  NOT special-cased. A same-file anchor citation
#     reproduces its own anchor, so the citing line is itself a match and the
#     anchor then matches twice — which this gate already reports as `2
#     matches`. A SYNTACTIC same-file rule was measured and rejected: every
#     skill file in this repo is named `SKILL.md`, so a basename comparison
#     flagged 3 CROSS-file citations as same-file. Match count catches the real
#     case without that false positive.
#
# ── EXCLUDED FROM THE WALK ────────────────────────────────────────────────────
# Four patterns, and every one of them is EMITTED as an EXCLUDED record carrying
# the file count it skipped — a silent exclusion would hide a third of the
# corpus:
#   docs/superpowers/**, docs/briefs/**, CHANGELOG.md   FROZEN RECORDS. Plans,
#     briefs and a changelog describe the tree as it WAS, and they hold ~150
#     line citations that are stale BY DESIGN.
#   tests/fixtures/**   CHECKER TEST DATA. A fixture tree is INPUT to a checker
#     and is deliberately malformed (tests/check-size-budgets.test.sh
#     (Fixture-prose caveat) records the same property for its own trees); this
#     gate's fixtures hold broken anchors on purpose, and its GOLDENS reproduce
#     those broken citations verbatim in the expected output. Scanning either
#     would make the gate fail on its own test data. Measured before the
#     exclusion was added: zero citation records came from tests/fixtures/, so
#     it costs no live coverage. The runners under tests/ ITSELF are still
#     scanned, and do carry live citations.
# `.git/` is pruned too, as machinery rather than policy, and is not reported.
# The exclusion applies to a file as a citation SOURCE, never as a citation
# TARGET: a live file may still cite into `docs/superpowers/`, and that anchor
# is resolved against the real file like any other.
#
# ── RESOLUTION MODEL ──────────────────────────────────────────────────────────
# Identical to scripts/resolve-citation.sh: literal substring, case-sensitive,
# LINE-SCOPED, lines split on LF only. The count is the number of MATCHING
# LINES, which is what resolve-citation emits one record per. `grep -a -c -F`
# has exactly that model — a trailing CR and a line-1 BOM can change a
# PREFIX-ANCHORED match but never a SUBSTRING one — so this leg uses it, and the
# pwsh twin's hand-rolled line loop returns the same count for the same bytes.
# OUT OF CONTRACT: files containing NUL bytes, same as resolve-citation.sh.
#
# Dependency-free: bash builtins plus `find`, `sort` and `grep` — no jq, no yq,
# no python, no YAML or markdown parser
# (.project/library-manifest.md#Adding a dependency (the gate)).
# bash-3.2-safe (macOS /bin/bash): no `declare -A`, no `mapfile`, no `${var,,}`.
set -u
# Byte-deterministic string model, mirroring scripts/resolve-citation.sh (Byte-deterministic string model):
# every class test, index and sort is byte-indexed, so this leg cannot desync
# from the pwsh UTF-16 twin on a multibyte line.
export LC_ALL=C

ROOT="${1:-$PWD}"
ROOT="${ROOT%/}"
[ -d "$ROOT" ] || { printf 'ERROR check-citations: not a directory: %s\n' "$ROOT" >&2; exit 1; }

# The path-class byte set, written once and reused in every glob below. `-` is
# LAST so it is a literal, not a range.
PC='A-Za-z0-9._/-'
WS=$' \t'

# Frozen-record patterns, in report order. A trailing `/` means "this prefix";
# anything else is an exact repo-relative path. Kept as three scalars rather
# than one array-of-pairs so bash 3.2 needs no associative array.
EX1='docs/superpowers/'; EXN1=0
EX2='docs/briefs/';      EXN2=0
EX3='CHANGELOG.md';      EXN3=0
EX4='tests/fixtures/';   EXN4=0

ok=0
failed=0
unverified=0

# is_citable_path <run> — discriminator rules 2 and 3.
is_citable_path() {
  case "$1" in */*) ;; *) return 1 ;; esac
  case "$1" in /*) return 1 ;; esac
  _b="${1##*/}"
  case "$_b" in *.*) ;; *) return 1 ;; esac
  _e="${_b##*.}"
  case "$_e" in ''|*[!A-Za-z0-9]*) return 1 ;; esac
  [ "${#_e}" -le 4 ] || return 1
  case "$_e" in *[A-Za-z]*) ;; *) return 1 ;; esac
  return 0
}

# balanced_end <text> — index of the `)` closing a paren opened just before
# <text>, or -1 when the parens never balance on this line. Byte-indexed under
# LC_ALL=C, so a multibyte anchor yields the index the pwsh twin's char scan
# yields: no UTF-8 continuation byte is `(` or `)`.
balanced_end() {
  _t="$1"; _d=1; _i=0; _n="${#_t}"
  while [ "$_i" -lt "$_n" ]; do
    _c="${_t:$_i:1}"
    if [ "$_c" = '(' ]; then
      _d=$((_d + 1))
    elif [ "$_c" = ')' ]; then
      _d=$((_d - 1))
      if [ "$_d" -eq 0 ]; then printf '%s' "$_i"; return 0; fi
    fi
    _i=$((_i + 1))
  done
  printf '%s' '-1'
}

# heading_end <text> — where a heading citation's text stops: the first
# backtick, comma, semicolon, double quote, or UNMATCHED `)`, else end of line.
# The paren-depth guard keeps a heading holding a BALANCED parenthetical whole
# (`… § Check if a PR already exists for this branch (re-run safety)`) while
# still cutting a markdown link target at its closing `)`
# (`](../README.md#the-layered-gating-model)`).
heading_end() {
  _t="$1"; _d=0; _i=0; _n="${#_t}"
  while [ "$_i" -lt "$_n" ]; do
    _c="${_t:$_i:1}"
    case "$_c" in
      '(') _d=$((_d + 1)) ;;
      ')') if [ "$_d" -eq 0 ]; then break; fi; _d=$((_d - 1)) ;;
      '`'|','|';'|'"') break ;;
    esac
    _i=$((_i + 1))
  done
  printf '%s' "$_i"
}

# rtrim <text> — strip trailing spaces and TABs.
rtrim() { _s="$1"; printf '%s' "${_s%"${_s##*[!$WS]}"}"; }

# match_count <file> <anchor> — matching LINE count, resolve-citation's model.
# `-a` forces text mode so a file grep guesses is binary still yields a count
# instead of "Binary file … matches"; `-F` makes the anchor a literal (a `.` or
# `*` in it matches only itself); `-e` protects an anchor starting with `-`.
# grep exits 1 on zero matches, so `|| true` keeps 0 a normal answer.
match_count() {
  _c="$(grep -a -c -F -e "$2" -- "$1" 2>/dev/null || true)"
  case "$_c" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$_c" ;;
  esac
}

# ---------------------------------------------------------------------------
# The walk. `find` enumerates every regular file under ROOT and prunes `.git`
# (a directory in a normal clone, a FILE in a linked worktree — the prune
# handles both). Paths are byte-sorted so the record stream is identical to the
# pwsh twin's, whose enumeration order is otherwise filesystem-defined.
# ---------------------------------------------------------------------------
TMPD="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/cc.$$")"; mkdir -p "$TMPD"
trap 'rm -rf "$TMPD"' EXIT
FILELIST="$TMPD/files"
KEPT="$TMPD/kept"
: > "$KEPT"

( cd "$ROOT" && find . -name .git -prune -o -type f -print ) \
  | sed 's|^\./||' | LC_ALL=C sort > "$FILELIST"

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  case "$rel" in
    "$EX1"*)  EXN1=$((EXN1 + 1)); continue ;;
    "$EX2"*)  EXN2=$((EXN2 + 1)); continue ;;
    "$EX3")   EXN3=$((EXN3 + 1)); continue ;;
    "$EX4"*)  EXN4=$((EXN4 + 1)); continue ;;
  esac
  printf '%s\n' "$rel" >> "$KEPT"
done < "$FILELIST"

printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX1" "$EXN1"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX2" "$EXN2"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX3" "$EXN3"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX4" "$EXN4"

# ---------------------------------------------------------------------------
# Scan. One pass per line, left to right: pull the next path-class run, test it
# as a path, then classify on the bytes that FOLLOW it.
# ---------------------------------------------------------------------------
while IFS= read -r rel; do
  src="$ROOT/$rel"
  [ -r "$src" ] || continue
  lno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lno=$((lno + 1))
    line="${line%$'\r'}"
    rest="$line"
    while [ -n "$rest" ]; do
      case "$rest" in *[$PC]*) ;; *) break ;; esac
      lead="${rest%%[$PC]*}"
      rest="${rest#"$lead"}"
      run="${rest%%[!$PC]*}"
      rest="${rest#"$run"}"
      is_citable_path "$run" || continue
      case "$rest" in
        ' ('*)
          after="${rest#' ('}"
          end="$(balanced_end "$after")"
          [ "$end" -gt 0 ] || continue
          anchor="${after:0:$end}"
          rest="${after:$((end + 1))}"
          tgt="$ROOT/$run"
          if [ -f "$tgt" ] && [ -r "$tgt" ]; then
            n="$(match_count "$tgt" "$anchor")"
          else
            n=0
          fi
          if [ "$n" -eq 1 ]; then
            printf 'OK\t%s:%s\t%s (%s)\n' "$rel" "$lno" "$run" "$anchor"
            ok=$((ok + 1))
          else
            printf 'FAIL\t%s:%s\t%s (%s)\t%s matches\n' "$rel" "$lno" "$run" "$anchor" "$n"
            failed=$((failed + 1))
          fi
          ;;
        '#'*)
          h="${rest#\#}"
          end="$(heading_end "$h")"
          head="$(rtrim "${h:0:$end}")"
          rest="${h:$end}"
          printf 'UNVERIFIED\t%s:%s\t%s#%s\tpath#Heading — not verified\n' "$rel" "$lno" "$run" "$head"
          unverified=$((unverified + 1))
          ;;
        ' § '*)
          h="${rest#' § '}"
          end="$(heading_end "$h")"
          head="$(rtrim "${h:0:$end}")"
          rest="${h:$end}"
          printf 'UNVERIFIED\t%s:%s\t%s § %s\tpath § Heading — not verified\n' "$rel" "$lno" "$run" "$head"
          unverified=$((unverified + 1))
          ;;
        :[0-9]*)
          spec="${rest#:}"
          d1="${spec%%[!0-9]*}"
          rest="${spec#"$d1"}"
          cite="$run:$d1"
          case "$rest" in
            -[0-9]*)
              d2="${rest#-}"
              d2="${d2%%[!0-9]*}"
              rest="${rest#-"$d2"}"
              cite="$cite-$d2"
              ;;
          esac
          printf 'UNVERIFIED\t%s:%s\t%s\tpath:line — not verified\n' "$rel" "$lno" "$cite"
          unverified=$((unverified + 1))
          ;;
      esac
    done
  done < "$src"
done < "$KEPT"

printf 'TOTALS\tunverified=%s\texcluded-files=%s\n' "$unverified" "$((EXN1 + EXN2 + EXN3 + EXN4))"
printf 'SUMMARY\tok=%s\tfailed=%s\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
