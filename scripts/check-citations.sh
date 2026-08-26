#!/usr/bin/env bash
# milestone-driver - repo-wide citation gate (issue #432).
#
# Walks a checked-out repo, finds every citation this repo writes, and RESOLVES
# the three forms that name a target inside the tree - `path (anchor)` per
# skills/citation-format.md (D1 - the `path (anchor)` form), and the two heading
# forms `path#Heading` and `path § Heading`. An anchor matching zero lines or
# more than one fails the run, and so does a heading matching zero headings or
# more than one.
#
# Why the gate exists: an anchor points at a literal string, so any edit to that
# string breaks the citation SILENTLY - it still looks well-formed and still
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
#   UNVERIFIED  <file>:<line>   <citation>   path:line - not verified
#   TOTALS      unverified=<U>  excluded-files=<E>
#   SUMMARY     ok=<N>          failed=<M>
# EXCLUDED records come first, then citation records in byte-sorted file order,
# then line order, then left-to-right within a line. Exit 0 when failed=0,
# exit 1 otherwise.
#
# ── WHAT A GREEN RUN DOES NOT VERIFY ──────────────────────────────────────────
# ONE form in skills/citation-format.md (The four forms) is COUNTED AND
# REPORTED, NEVER RESOLVED:
#   `path:line` / `path:start-end`  A line number is not checkable without an
#     author-supplied expected token, which this repo does not carry. Reporting
#     one and calling the run green would be the false assurance issue #407
#     warned about.
# So `failed=0` means "every anchor still points at its string and every cited
# heading still exists, exactly once", NOT "every citation in this repo is
# good". The position test is still not applied (see below), and a `path:line`
# citation is still nobody's to check.
#
# THE HEADING FORMS WERE UNVERIFIED UNTIL THIS GATE LEARNED THREE THINGS, and
# each is why the earlier measurement saw 23 FAIL records against 23 citations
# it read as CORRECT:
#   13 GitHub-SLUG headings (`#the-mechanical-gates` against a real
#     `## The mechanical gates`). Those were never correct - D1's heading form
#     names the heading TEXT, and scripts/read-doc-section.sh matches it
#     case-sensitively and exactly, so a slug resolved nowhere. All 13 are now
#     spelled as their heading text.
#   8 MARKDOWN LINK TARGETS, which are not citations at all. Discriminator rule
#     5 below drops them on the two bytes standing before the path.
#   2 headings HOLDING BACKTICKS that a backtick-delimited token cannot bound.
#     A citation whose heading holds a backtick has no writable spelling in
#     either heading form; write `path:line` for that section instead.
# A heading holding DOUBLE QUOTES is not one of those shapes and needs nothing
# special: inside a code span only the closing backtick bounds the heading, so
# `#### 6.9 Surface in the final summary "Your move" section` resolves as
# written (see heading_end below).
#
# ── WHAT COUNTS AS A CITATION (the discriminator) ─────────────────────────────
# skills/citation-format.md (What marks it as a citation) makes the code span
# the discriminator: a citation is one whole backtick-wrapped token. That rule
# is expressed here POSITIONALLY, which needs no backtick tracking and no
# markdown parser:
#
#   1. A PATH-CLASS RUN. The path is a maximal run of [A-Za-z0-9._/-]. Every
#      other byte - backtick, space, quote, `<`, `>`, `$`, `{` - ends the run,
#      and the citation form is decided by the bytes that FOLLOW it. This is
#      what kills the prose lookalikes the format file names: in
#      `` `agents/triage-reviewer.md` (architect lens) `` a CLOSING BACKTICK
#      sits where the citation's space would be, so what follows the path is not
#      ` (` and the phrase is prose. Same for `` `skills/setup/SKILL.md`
#      (Phase 2) ``, `` `.claude/settings.json` (project) `` and
#      `` `package.json` (generic Node) ``. No special-casing.
#   2. THE RUN MUST CONTAIN `/`. Measured: removes 24 further prose lookalikes
#      at ZERO cost to a real citation. The dominant class is this repo's own
#      test-runner header line, 18 of them, shaped `# milestone-driver -
#      golden-matrix runner for build-file-index.ps1 (issue #318).`
#   3. THE RUN MUST NOT START WITH `/`, and must end in an extension of 1–4
#      alphanumeric bytes holding at least one letter. Rule 1 already cuts
#      `<repo>` off `<repo>/.milestone-config/driver.json (…)`, leaving a run
#      that starts with `/`; the extension test drops version shapes like
#      `1.2 (…)` and bare prose like `Fail-loud (fail-CLOSED)`.
#   4. THE ANCHOR IS BOUNDED BY PAREN BALANCE, not by the final `)` on the line.
#      This is what recovers the nested anchors this repo really writes -
#      scripts/read-doc-section.sh (Fail-loud (fail-CLOSED)),
#      scripts/build-file-index.sh (extract_symbols() {),
#      scripts/read-doc-section.ps1 (if ($args.Count -ne 2) {) - and what drops
#      a prose parenthetical that runs off the end of the line without closing
#      (4 of them live, e.g. `.gitignore`'s wrapped settings comment).
#   5. A MARKDOWN LINK TARGET IS NOT A CITATION. The two bytes standing
#      immediately before the run are the whole test: `](` there means the path
#      is the target half of `[text](path#anchor)`, which is a link the reader
#      follows, never an evidence reference. Without the rule every such target
#      reached the heading resolver as a slug and failed against a real heading
#      - 8 of them when the heading forms were first measured. The rule is
#      POSITIONAL like rules 1 to 4 and needs no markdown parser.
# Measured against this repo on a clean tree: 168 anchor citations, all 168
# resolving to exactly one line.
#
# THE POSITION TEST IS NOT APPLIED. skills/citation-format.md also requires a
# citation to stand in a citation position (an evidence slot, or a grounding
# reference). That is a model judgment, not a mechanical one - see
# skills/solve-issue/SKILL.md (never a regex). This script deliberately runs the
# SPAN test only, and the four rules above are calibrated so that on this tree
# the span test alone has no false positives.
#
# ── EDGE CASES, AND THE CHOICE MADE FOR EACH ──────────────────────────────────
#   Prose that looks like a citation  Dropped by rules 1-4. NOT reported: a
#     prose parenthetical is not a citation and never was.
#   Heading ending in a parenthetical  A heading citation splits on the
#     SEPARATOR, never the parenthesis: the path-class run ends at `#`, so the
#     classifier sees the heading form and never reaches the ` (`. The live
#     example is library-manifest's "Adding a dependency (the gate)" heading,
#     cited seven times, and it resolves as written.
#   A heading form against a file that HOLDS NO HEADINGS  `0 matches`, like any
#     other miss. A JSON or shell target has no ATX heading to name, so the
#     anchor form is the form to write for it.
#   A DUPLICATE heading  `<n> matches`, a FAIL. scripts/read-doc-section.sh
#     takes the first and succeeds; this gate refuses, exactly as it refuses a
#     non-unique anchor. See heading_count below for why the two differ.
#   `${CLAUDE_PLUGIN_ROOT}/` paths  `$`, `{` and `}` are not path-class, so the
#     run starts at the `/` after `}` and is dropped by rule 3 (leading `/`).
#     Never reported as missing. None is written in the anchor form today; if
#     one ever is, it goes UNREPORTED rather than failing.
#   Cross-repo citations  Not distinguishable from a local path by shape. Every
#     live one is a LINE form - `skills/output-style.md` cites milestone-feeder's
#     `agents/issue-author.md` by line range - so every live one lands in
#     UNVERIFIED and cannot fail the build. A cross-repo ANCHOR OR HEADING
#     citation fails as `0 matches`, and CONTAINMENT is what makes that true
#     rather than accidental: see in_tree() below. Without it, an anchor citation of a
#     dot-dot path READ A FILE NEXT TO THE CHECKOUT and reported OK, so the same
#     citation answered differently depending on where the tree sat on disk.
#   Anchor paths that escape the checkout  Resolved ONLY against the walked file
#     set, so `..`, an absolute path, a symlink out of the tree and a
#     non-regular file are all `0 matches` rather than a read of whatever
#     happens to sit there. citation-format.md's repo-root base rule is the
#     contract this enforces.
#   Bare `:NNN` continuations  A token with no path before the colon has no
#     path-class run, so it is never picked up - skipped by construction. It
#     carries no path to check.
#   Same-file citations  NOT special-cased. A same-file anchor citation
#     reproduces its own anchor, so the citing line is itself a match and the
#     anchor then matches twice - which this gate already reports as `2
#     matches`. A SYNTACTIC same-file rule was measured and rejected: every
#     skill file in this repo is named `SKILL.md`, so a basename comparison
#     flagged 3 CROSS-file citations as same-file. Match count catches the real
#     case without that false positive.
#
# ── EXCLUDED FROM THE WALK ────────────────────────────────────────────────────
# Six patterns, and every one of them is EMITTED as an EXCLUDED record carrying
# the file count it skipped - a silent exclusion would hide a third of the
# corpus.
#
# ONE CLASS, six spellings: content that is historical, generated, or
# deliberately malformed, and therefore holds stale citations BY DESIGN. None of
# it is code a reader of this repo is asked to trust, and every one of the six is
# either committed-but-frozen or gitignored per-clone scratch:
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
#   .milestone-config/worktrees/**   ANOTHER CHECKOUT, NOT THIS ONE. The driver
#     builds a git worktree per issue there, so each one is a WHOLE SECOND COPY
#     of the repo sitting inside the tree being walked. Two effects, and the
#     second is the one that bites: every citation gets counted once per live
#     worktree, and - because the exclusions above are REPO-RELATIVE PREFIXES -
#     a worktree's own `tests/fixtures/` reads as
#     `.milestone-config/worktrees/issue-N/tests/fixtures/`, matches NO
#     exclusion, and its deliberately-broken fixture anchors FAIL THE RUN.
#     Measured on this repo with two worktrees live: 58 FAIL records, every one
#     of them a fixture citation that is broken ON PURPOSE, against a tree whose
#     TRACKED files were clean. CI never sees it - a fresh checkout has no
#     worktrees - so the gate went red only for the person running the driver,
#     which is every real run. Excluded as a SOURCE only, like the others.
#   .milestone-feeder/**   A SIBLING PLUGIN'S PER-RUN SCRATCH. milestone-feeder
#     writes its plan file, needs-input report and authoring temp files there
#     (gitignored, `/.milestone-feeder/` in .gitignore). A plan describes the
#     tree as it WAS at planning time, so its citations go stale exactly the way
#     docs/briefs/** does - same class, different author. Measured on this repo:
#     11 FAIL records, every one a plan or resolved-body file naming an anchor
#     that has since been reworded. Like the worktrees, CI never sees it and a
#     fresh clone has none, so the cost landed entirely on the person running the
#     tools. A gate that is red BY DEFAULT on any machine with feeder scratch on
#     disk is a gate people stop reading, and that costs more than the coverage
#     it buys.
#   (gitignored)   WHATEVER GIT SAYS IS IGNORED, and it is not a path pattern
#     but a set, reported last so the six patterns above keep their counts. A
#     gitignored file is per-clone scratch BY DEFINITION: it is absent from a
#     fresh checkout, so anything it says is invisible to CI and visible only to
#     the person running the tools. Measured on this repo: a per-clone
#     `.milestone-config/triage-cache.json` produced 2 FAIL records locally
#     against a tree CI read as clean, and a gate that is red locally and green
#     in CI is a gate people stop reading. The six patterns above are checked
#     FIRST and this set LAST, so a file matching both is counted once, in the
#     pattern's row.
# `.git/` is pruned too, as machinery rather than policy, and is not reported.
# The exclusion applies to a file as a citation SOURCE, never as a citation
# TARGET: a live file may still cite into `docs/superpowers/`, and that anchor
# is resolved against the real file like any other.
#
# ── RESOLUTION MODEL ──────────────────────────────────────────────────────────
# TWO models, one per form family. The HEADING forms use
# scripts/read-doc-section.sh's ATX heading rule, in heading_count below. The
# ANCHOR form's is this one, identical to scripts/resolve-citation.sh: literal
# substring, case-sensitive,
# LINE-SCOPED, lines split on LF only. The count is the number of MATCHING
# LINES, which is what resolve-citation emits one record per. `grep -a -c -F`
# has exactly that model - a trailing CR and a line-1 BOM can change a
# PREFIX-ANCHORED match but never a SUBSTRING one - so this leg uses it, and the
# pwsh twin's hand-rolled line loop returns the same count for the same bytes.
# OUT OF CONTRACT: files containing NUL bytes, same as resolve-citation.sh.
#
# Dependency-free: bash builtins plus `find`, `sort` and `grep` - no jq, no yq,
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

# Walk-exclusion patterns, in report order. A trailing `/` means "this prefix";
# anything else is an exact repo-relative path. Kept as flat scalars rather
# than one array-of-pairs so bash 3.2 needs no associative array.
EX1='docs/superpowers/'; EXN1=0
EX2='docs/briefs/';      EXN2=0
EX3='CHANGELOG.md';      EXN3=0
EX4='tests/fixtures/';   EXN4=0
EX5='.milestone-config/worktrees/'; EXN5=0
EX6='.milestone-feeder/';           EXN6=0
# EX7 is not a path pattern: it is the set git reports as IGNORED under
# ROOT. See the gitignore note in the walk section below.
EX7='(gitignored)';                 EXN7=0

ok=0
failed=0
unverified=0

# is_citable_path <run> - discriminator rules 2 and 3.
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

# balanced_end <text> - index of the `)` closing a paren opened just before
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

# heading_end <text> <mode> - where a heading citation's text stops. <mode> is
# `span` when the path was immediately preceded by a backtick and `bare`
# otherwise, and the two are bounded differently ON PURPOSE:
#
#   span   ONLY the closing backtick ends the heading. This is
#          skills/citation-format.md (What marks it as a citation) read
#          literally: a citation is one whole backtick-wrapped token, so inside
#          a span the delimiter IS the bound and it is EXACT. Nothing else may
#          cut it - a real heading legitimately holds quotes
#          (`… § 6.9 Surface in the final summary "Your move" section`), commas
#          and parentheses, and every one of those was truncating a correct
#          citation before.
#   bare   No span exists, so no exact bound exists either and the rule is a
#          conservative stop, FIVE of them: backtick, UNMATCHED `)`, comma,
#          semicolon, double quote. The paren-depth guard keeps a heading
#          holding a BALANCED parenthetical whole, which is what lets a bare
#          reference to "Adding a dependency (the gate)" resolve from inside a
#          shell comment. A spaced hyphen is deliberately NOT a stop, in either
#          mode: it is ordinary text inside this repo's headings and anchors, so
#          stopping on it would cut a correct anchor at its first hyphen and
#          fail the gate repo-wide.
#          A bare bound is a GUESS, and the guess is wrong the moment the
#          sentence continues past the heading with none of the five stops in
#          between. Wrap the citation in a code span when that happens; two
#          comment lines in this repo needed it.
heading_end() {
  _t="$1"; _m="$2"; _d=0; _i=0; _n="${#_t}"
  while [ "$_i" -lt "$_n" ]; do
    _c="${_t:$_i:1}"
    [ "$_c" = '`' ] && break
    if [ "$_m" = bare ]; then
      case "$_c" in
        '(') _d=$((_d + 1)) ;;
        ')') if [ "$_d" -eq 0 ]; then break; fi; _d=$((_d - 1)) ;;
        ','|';'|'"') break ;;
      esac
    fi
    _i=$((_i + 1))
  done
  printf '%s' "$_i"
}

# rtrim <text> - strip trailing spaces and TABs.
rtrim() { _s="$1"; printf '%s' "${_s%"${_s##*[!$WS]}"}"; }

# match_count <file> <anchor> - matching LINE count, resolve-citation's model.
# `-a` forces text mode so a file grep guesses is binary still yields a count
# instead of "Binary file … matches"; `-F` makes the anchor a literal (a `.` or
# `*` in it matches only itself); `-e` protects an anchor starting with `-`.
# grep exits 1 on zero matches, so `|| true` keeps 0 a normal answer.
match_count() {
  # Size guard, the READ half of the walk's LIST/READ split: a 0-byte target has
  # nothing to match, and refusing to open one is what keeps `grep` off a FIFO.
  [ -s "$1" ] || { printf '0'; return 0; }
  _c="$(grep -a -c -F -e "$2" -- "$1" 2>/dev/null || true)"
  case "$_c" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$_c" ;;
  esac
}

# heading_count <file> <heading> - the number of ATX HEADING LINES in <file>
# whose text equals <heading> exactly. The match rule is
# scripts/read-doc-section.sh (Match rule) verbatim, and it has to be: this gate
# is green exactly when that resolver succeeds. Leading `#`s are counted, a
# space or end-of-line must follow them, and the remainder is compared
# CASE-SENSITIVE after trimming whitespace at both ends. A trailing CR is
# stripped first, so a CRLF checkout answers the same as an LF one.
#
# ONE DIVERGENCE FROM THE RESOLVER, DELIBERATE: read-doc-section takes the FIRST
# of two identical headings and succeeds; this gate reports `2 matches` and
# FAILS, the same call this gate already makes on a non-unique anchor. A
# citation naming one of two identical sections does not say which, and only its
# author can.
heading_count() {
  [ -s "$1" ] || { printf '0'; return 0; }
  _hc=0
  while IFS= read -r _hl || [ -n "$_hl" ]; do
    _hl="${_hl%$'\r'}"
    case "$_hl" in '#'*) ;; *) continue ;; esac
    _hr="$_hl"
    while [ "${_hr#'#'}" != "$_hr" ]; do _hr="${_hr#'#'}"; done
    case "$_hr" in ''|' '*) ;; *) continue ;; esac
    _ht="${_hr#"${_hr%%[![:space:]]*}"}"
    _ht="${_ht%"${_ht##*[![:space:]]}"}"
    [ "$_ht" = "$2" ] && _hc=$((_hc + 1))
  done < "$1"
  printf '%s' "$_hc"
}

# resolve_heading <run> <heading> - match count for a heading citation, and 0
# when the target sits outside the walked file set. Containment is the same rule
# and the same reason as the anchor form's, see in_tree below.
resolve_heading() {
  if in_tree "$1"; then heading_count "$ROOT/$1" "$2"; else printf '0'; fi
}

# in_tree <repo-relative-path> - CONTAINMENT. True only when the path is a
# MEMBER OF THE WALKED FILE SET, which is the set `find -type f` produced under
# ROOT. Membership is the containment test, and it is stronger than a lexical
# `..` check: the walked set holds no path outside ROOT, no symlink (find
# without -L lists none), no directory, and no FIFO/socket/device node, so an
# anchor can only ever be resolved against a regular file inside this checkout.
# WHY IT IS REQUIRED: without it, an anchor citation naming a dot-dot path
# opened a file NEXT TO the checkout and reported OK. That is not hypothetical -
# driver runs from `.milestone-config/worktrees/issue-N`, where `..` points
# somewhere entirely different than it does in a plain clone, so the same
# citation would answer differently depending on where the tree sits on disk.
# Measured before adding it: no live anchor citation uses `..`, so containment
# costs zero coverage; the 4 live `../README.md` records are heading forms,
# which are never resolved.
# `-x` anchors the match to the WHOLE line and `-F` keeps it literal, so a path
# is never a prefix-match of a longer sibling; `-e` protects a leading dash.
in_tree() { grep -qxF -e "$1" -- "$FILELIST" 2>/dev/null; }

# ---------------------------------------------------------------------------
# The walk. `find` LISTS every entry under ROOT that is NOT A DIRECTORY and NOT
# A SYMLINK, and prunes `.git` (a directory in a normal clone, a FILE in a
# linked worktree - the prune handles both). Paths are byte-sorted so the record
# stream is identical to the pwsh twin's, whose enumeration order is otherwise
# filesystem-defined.
#
# LIST and READ are two different tests, and that split is what keeps the twins
# byte-identical:
#   LIST   not a directory, not a symlink. `-type f` would have been the tighter
#          rule, but .NET on Unix EXPOSES NO REGULAR-FILE BIT - probed on pwsh
#          7.6.3, a FIFO reports FileAttributes.Normal and UnixMode `-rw-r--r--`,
#          both identical to a regular file - so `-type f` is a test the pwsh
#          twin cannot reproduce, and the two legs' EXCLUDED counts would drift
#          apart on any tree holding a non-regular entry. "Not a directory, not
#          a symlink" is computable on both legs, exactly.
#   READ   size greater than zero, tested just before the scan loop and again
#          before a target is searched. This is what makes the looser LIST rule
#          safe: a FIFO, a socket and a device node all stat as 0 bytes, so
#          neither leg ever OPENS one, and a FIFO blocks forever on open (the
#          pwsh leg used to hang a CI job to timeout on exactly that). A 0-byte
#          REGULAR file is skipped by the same test and loses nothing: it has no
#          lines to scan and no bytes to match.
# The three 0-byte files in this repo's fixtures are why the split is not
# theoretical - `find -type f` counted them and the pwsh walk did not, a 3-file
# gap in the EXCLUDED record.
#
# find's OWN stderr is discarded, deliberately. An unreadable subdirectory makes
# find warn and keep going, and that warning's TEXT IS NOT PORTABLE: BSD find
# writes `find: ./locked: Permission denied` while GNU find quotes the path,
# `find: ‘./locked’: Permission denied`. Keeping it would make this leg's stderr
# differ between macOS and the ubuntu CI runner, and no pwsh twin can reproduce
# either spelling. Both legs therefore say NOTHING on stderr for an unreadable
# directory and simply skip what they cannot read, which keeps stdout, stderr
# and the exit code identical across legs and across hosts. An unreadable
# directory is an environment fault, not a citation defect, and this gate has no
# opinion on it.
# ---------------------------------------------------------------------------
TMPD="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/cc.$$")"; mkdir -p "$TMPD"
trap 'rm -rf "$TMPD"' EXIT
FILELIST="$TMPD/files"
KEPT="$TMPD/kept"
: > "$KEPT"

( cd "$ROOT" && find . -name .git -prune -o ! -type d ! -type l -print 2>/dev/null ) \
  | sed 's|^\./||' | LC_ALL=C sort > "$FILELIST"

# The IGNORED set: every path under ROOT git reports as ignored. ONE call, and
# its failure mode is an EMPTY set - git absent, ROOT outside a work tree, or
# any other nonzero exit leaves the file empty and nothing is excluded, which is
# the direction that scans MORE rather than less. `-c core.quotePath=false`
# stops git escaping the non-ASCII bytes of a path; it does NOT stop C-quoting a
# path holding `"`, a backslash or a control byte, and such a path simply misses
# the exact match below and stays in the walk.
IGNORED="$TMPD/ignored"
: > "$IGNORED"
git -C "$ROOT" -c core.quotePath=false ls-files --others --ignored --exclude-standard \
  > "$IGNORED" 2>/dev/null || : > "$IGNORED"

# is_ignored <repo-relative-path> - membership in that set. `-x` anchors the
# match to the WHOLE line and `-F` keeps it literal, so a path is never a
# prefix-match of a longer sibling; `-e` protects a leading dash.
is_ignored() { grep -qxF -e "$1" -- "$IGNORED" 2>/dev/null; }

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  case "$rel" in
    "$EX1"*)  EXN1=$((EXN1 + 1)); continue ;;
    "$EX2"*)  EXN2=$((EXN2 + 1)); continue ;;
    "$EX3")   EXN3=$((EXN3 + 1)); continue ;;
    "$EX4"*)  EXN4=$((EXN4 + 1)); continue ;;
    "$EX5"*)  EXN5=$((EXN5 + 1)); continue ;;
    "$EX6"*)  EXN6=$((EXN6 + 1)); continue ;;
  esac
  if is_ignored "$rel"; then EXN7=$((EXN7 + 1)); continue; fi
  printf '%s\n' "$rel" >> "$KEPT"
done < "$FILELIST"

printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX1" "$EXN1"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX2" "$EXN2"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX3" "$EXN3"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX4" "$EXN4"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX5" "$EXN5"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX6" "$EXN6"
printf 'EXCLUDED\t%s\tskipped=%s\n' "$EX7" "$EXN7"

# ---------------------------------------------------------------------------
# Scan. One pass per line, left to right: pull the next path-class run, test it
# as a path, then classify on the bytes that FOLLOW it.
# ---------------------------------------------------------------------------
while IFS= read -r rel; do
  src="$ROOT/$rel"
  [ -r "$src" ] || continue
  # READ half of the LIST/READ split - see the walk comment above.
  [ -s "$src" ] || continue
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
      # Byte offset of the run's first byte, hence of the byte BEFORE it. A
      # backtick there means the citation opens a code span, which is the only
      # exact bound a heading citation ever has (see heading_end).
      runpos=$(( ${#line} - ${#rest} - ${#run} ))
      # Discriminator rule 5: a MARKDOWN LINK TARGET is not a citation. `](`
      # standing immediately before the run is the whole test - see the header.
      if [ "$runpos" -ge 2 ] && [ "${line:$((runpos - 2)):2}" = '](' ]; then
        continue
      fi
      if [ "$runpos" -gt 0 ] && [ "${line:$((runpos - 1)):1}" = '`' ]; then
        hmode=span
      else
        hmode=bare
      fi
      case "$rest" in
        ' ('*)
          after="${rest#' ('}"
          end="$(balanced_end "$after")"
          [ "$end" -gt 0 ] || continue
          anchor="${after:0:$end}"
          rest="${after:$((end + 1))}"
          if in_tree "$run"; then
            n="$(match_count "$ROOT/$run" "$anchor")"
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
          end="$(heading_end "$h" "$hmode")"
          head="$(rtrim "${h:0:$end}")"
          rest="${h:$end}"
          n="$(resolve_heading "$run" "$head")"
          if [ "$n" -eq 1 ]; then
            printf 'OK\t%s:%s\t%s#%s\n' "$rel" "$lno" "$run" "$head"
            ok=$((ok + 1))
          else
            printf 'FAIL\t%s:%s\t%s#%s\t%s matches\n' "$rel" "$lno" "$run" "$head" "$n"
            failed=$((failed + 1))
          fi
          ;;
        ' § '*)
          h="${rest#' § '}"
          end="$(heading_end "$h" "$hmode")"
          head="$(rtrim "${h:0:$end}")"
          rest="${h:$end}"
          n="$(resolve_heading "$run" "$head")"
          if [ "$n" -eq 1 ]; then
            printf 'OK\t%s:%s\t%s § %s\n' "$rel" "$lno" "$run" "$head"
            ok=$((ok + 1))
          else
            printf 'FAIL\t%s:%s\t%s § %s\t%s matches\n' "$rel" "$lno" "$run" "$head" "$n"
            failed=$((failed + 1))
          fi
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
          printf 'UNVERIFIED\t%s:%s\t%s\tpath:line - not verified\n' "$rel" "$lno" "$cite"
          unverified=$((unverified + 1))
          ;;
      esac
    done
  done < "$src"
done < "$KEPT"

printf 'TOTALS\tunverified=%s\texcluded-files=%s\n' "$unverified" "$((EXN1 + EXN2 + EXN3 + EXN4 + EXN5 + EXN6 + EXN7))"
printf 'SUMMARY\tok=%s\tfailed=%s\n' "$ok" "$failed"
[ "$failed" -eq 0 ]
