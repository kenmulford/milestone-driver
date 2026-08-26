#!/usr/bin/env bash
# milestone-driver - review-depth classifier (issue #598).
#
# Answers ONE question about a built diff: how much review does it deserve? The
# answer picks the reviewer's effort and cycle count, so it must be mechanical
# and it must be the same answer on every host.
#
# Usage:   classify-review-depth.sh [REPO_ROOT]
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#
# Output (stdout), exactly one line, newline-terminated:
#   deep        the diff touches hooks/**, adds a file under sourceGlobs, or
#               changes only one leg of a .sh/.ps1 twin pair
#   standard    the diff touches some other path under sourceGlobs
#   shallow     the diff touches no path under sourceGlobs
# Output (stderr), exactly one token, and only when there is a specific trigger
# to name:
#   hooks:<path>       the first candidate under hooks/
#   new-file:<path>    the first added candidate under sourceGlobs
#   twin:<path>        a .sh or .ps1 candidate under sourceGlobs whose opposite
#                      leg is not in the candidate set
#   no-git             git is not on PATH
#   no-diff            `git diff HEAD` failed - not a repo, or no HEAD
#   empty-candidates   git named no changed and no untracked path
#   no-jq              jq is not on PATH
#   no-config          neither <root>/.milestone-config/driver.json nor the
#                      legacy <root>/milestone-driver.json is readable
#   no-source-globs    that config yielded no usable sourceGlobs entry
#   rejected-path:<p>  the first candidate whose shape disqualified it, so it
#                      was matched against nothing (see PATH SHAPE)
# An ordinary standard or shallow verdict carries no reason. Exit is ALWAYS 0,
# mirroring `scripts/classify-delta.sh (Exit is ALWAYS 0)`: the verdict is the
# output, not the exit code.
#
# THE SAFE DIRECTION IS MORE REVIEW, and every degrade resolves that way -
# standard, never shallow. A wrong `deep` costs one extra review cycle; a wrong
# `shallow` ships an unreviewed diff. That is why the seven failure tokens above
# all emit `standard` (`.project/design-philosophy.md#Error & failure philosophy`).
#
# WHAT THE CANDIDATE SET IS, and what it is NOT. Exactly two git reads:
# `git diff --name-status HEAD` and
# `git ls-files --others --exclude-standard --full-name`. Nothing else. No
# `find`, no `ls -R`, no globstar expansion against the filesystem, no directory
# recursion, no stat, no existence check.
#
# `HEAD`, not bare `git diff`: a denied commit at `hooks/tests-green.sh` exit 2
# leaves the tree staged, and bare `git diff` then prints nothing. Here that
# would read as an empty candidate set on a real code change - and `standard`
# on a diff that had earned `deep`. Diffing against HEAD sees staged and
# unstaged work alike, the same hazard
# `scripts/classify-delta.sh (WHAT THE DELTA IS)` records.
#
# `--no-renames`, so every diff line is one status and one path. A rename then
# arrives as a delete plus an add, and its new path counts as a new file - which
# is the right reading anyway, because a moved source file is a new path under
# sourceGlobs that no reviewer has seen.
#
# `--full-name` on the ls-files read, so both git reads name paths from the same
# base. `diff --name-status` always reports from the repo top; ls-files without
# the flag reports relative to the directory it runs in. A REPO_ROOT below the
# top - a package subdir carrying its own driver.json - would otherwise put two
# path bases in one candidate set, both matched against one repo-relative
# sourceGlobs.
#
# `-c core.quotePath=false` stops git escaping the non-ASCII bytes of a path. It
# does NOT stop C-quoting, which git applies whatever that setting says to any
# path holding `"`, a backslash, or a control character: such a path arrives
# wrapped in double quotes with its own quotes backslash-escaped, a spelling
# that matches no glob. The path-shape guard rejects that spelling outright
# rather than letting it read as a path under no sourceGlob.
#
# THE TWIN TEST IS PURELY SET-MEMBERSHIP, never an existence check: a `.sh`
# candidate is deep unless its `.ps1` sibling is ALSO in the candidate set.
# Asking the filesystem or the index whether the sibling exists at all would be
# the more precise rule, and it is the rule this script may not have - the
# candidate set is the only ground it is allowed to stand on. The imprecision
# runs one way only, per the SAFE DIRECTION rule above: a `.sh` file that never
# had a twin classifies deep.
#
# hooks/** IS CHECKED AGAINST EVERY CANDIDATE, not only the ones under
# sourceGlobs, and it is checked BEFORE the config is read. In this repo
# hooks/** is a sourceGlobs entry, so the two readings agree; in a consumer repo
# that omits it, an unreviewed hook change is exactly the outcome the deep row
# exists to prevent. The trigger is a fixed literal prefix, not a configured
# glob, so it needs neither sourceGlobs nor jq - and ordering it after the
# config read would have handed a repo with no driver.json, or a jq-less host,
# the `standard` degrade on a hook change. The SAFE DIRECTION rule above is not
# safe enough here: standard on hooks/** is still a downgrade.
#
# PATH SHAPE IS ENFORCED ON BOTH SIDES, candidates and configured globs alike:
# a path that is absolute (leading `/`, or a `C:/` drive prefix), starts with
# `~`, starts with the `"` of git's C-quoted spelling, or contains `..` is
# rejected. The `..` test is a plain substring test, so a legitimate file named
# `a..b.sh` is rejected too. That is deliberate: a rule with no exceptions
# cannot be argued around, and the alternative - parsing path components to tell
# traversal from a filename - is the kind of parse this script exists to avoid.
# Git cannot emit an absolute or a `~` path for a repo-relative candidate, so
# those two are really aimed at a hand-edited sourceGlobs entry; the C-quote
# rule is aimed at git itself.
#
# A REJECTED CANDIDATE FLOORS THE VERDICT AT `standard` and names itself in
# `rejected-path:<p>`. Nothing was ever matched against it, so `shallow` would
# be a claim about a path this script deliberately refused to read, and the SAFE
# DIRECTION rule above settles which way that resolves. The floor is applied
# LAST, after every deep trigger has had its say, so a rejection can only raise
# a `shallow` to `standard`, never lower a `deep`.
#
# THE GLOB SUBSET IS THREE WILDCARDS, translated once into an ERE:
#   **/  ->  (.*/)?    so `**/*.md` matches `x.md` as well as `sub/x.md`
#   **   ->  .*        any run of bytes, `/` included
#   *    ->  [^/]*     any run of bytes within one path segment
#   ?    ->  [^/]      one byte within one path segment
# Every other byte is a literal, backslash-escaped when it is an ERE
# metacharacter. Character classes are NOT supported - a `[` in a glob is a
# literal `[`. The pwsh twin translates to the identical pattern and matches it
# with .NET's regex engine, which agrees with POSIX ERE on exactly this subset.
#
# THIS IS NOT THE REPO'S ONLY sourceGlobs MATCHER, and the three do not agree
# everywhere. `hooks/tests-green.sh` and `hooks/force-subagent.sh` collapse `**`
# to `*` and match with a shell `case` instead. All three agree on `dir/**`, the
# shape every sourceGlobs entry in this repo takes. They part on `**/*.ext`: the
# `(.*/)?` above matches a ROOT-level `x.md`, and tests-green's collapsed
# `*/*.md` does not - while force-subagent lands back on this file's answer
# through a second test, of the ABSOLUTE path against `*/<pat>`. Pinned as
# behavior, not endorsed as a contract:
# `tests/classify-review-depth.cases.tsv (standard_globstar_prefix_optional)`.
# Aligning the three is its own issue: the two hooks decide whether the unit
# suite runs and whether a source edit is blocked, and this one only decides how
# hard the diff is reviewed.
set -u
# Byte-indexed string ops and byte-range bracket expressions, so this leg and
# the pwsh twin's byte model agree on every boundary test - `?` and `[^/]` are
# one BYTE in both legs (`scripts/extract-version.sh (Force a deterministic byte model)`).
export LC_ALL=C

ROOT="${1:-$PWD}"
ROOT="${ROOT%/}"
TAB=$'\t'

# emit <verdict> [reason]
emit() {
  printf '%s\n' "$1"
  [ -n "${2:-}" ] && printf '%s' "$2" >&2
  exit 0
}

# valid_path <path> -> 0 when the path is repo-relative and forward-slash.
valid_path() {
  case "$1" in
    '') return 1 ;;
    /*|~*|'"'*) return 1 ;;
    *..*) return 1 ;;
    [A-Za-z]:/*) return 1 ;;
  esac
  return 0
}

# in_list <needle> <newline-separated list> -> 0 when the list holds the needle.
in_list() {
  local needle="$1" x
  while IFS= read -r x; do
    [ "$x" = "$needle" ] && return 0
  done <<EOF
$2
EOF
  return 1
}

# glob_to_re <glob> -> the glob as an ERE body (no anchors).
glob_to_re() {
  local g="$1" out='' i=0 n="${#g}" c
  local meta='.^$+()[]{}|\'
  while [ "$i" -lt "$n" ]; do
    c="${g:$i:1}"
    if [ "$c" = '*' ]; then
      if [ "${g:$((i + 1)):1}" = '*' ]; then
        if [ "${g:$((i + 2)):1}" = '/' ]; then
          out="$out(.*/)?"; i=$((i + 3))
        else
          out="$out.*"; i=$((i + 2))
        fi
      else
        out="$out[^/]*"; i=$((i + 1))
      fi
      continue
    fi
    if [ "$c" = '?' ]; then
      out="$out[^/]"; i=$((i + 1)); continue
    fi
    case "$meta" in
      *"$c"*) out="$out\\$c" ;;
      *) out="$out$c" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# ---- 1. the candidate set, from git and from nothing else.
command -v git >/dev/null 2>&1 || emit 'standard' 'no-git'

delta="$(git -C "$ROOT" -c core.quotePath=false --no-pager diff --no-color \
  --no-renames --name-status HEAD 2>/dev/null)" || emit 'standard' 'no-diff'
others="$(git -C "$ROOT" -c core.quotePath=false ls-files --others \
  --exclude-standard --full-name 2>/dev/null)" || others=''

CANDIDATES=''
NEWSET=''
raw=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  raw=$((raw + 1))
  p="${line#*"$TAB"}"
  CANDIDATES="$CANDIDATES$p
"
  case "${line%%"$TAB"*}" in
    A*) NEWSET="$NEWSET$p
" ;;
  esac
done <<EOF
$delta
EOF
while IFS= read -r line; do
  [ -n "$line" ] || continue
  raw=$((raw + 1))
  CANDIDATES="$CANDIDATES$line
"
  NEWSET="$NEWSET$line
"
done <<EOF
$others
EOF
[ "$raw" -eq 0 ] && emit 'standard' 'empty-candidates'

# ---- 2. drop the candidates whose shape disqualifies them, keeping the first
# one dropped: step 6 floors the verdict at `standard` when there is one.
VALID=''
REJECTED=''
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if valid_path "$p"; then
    VALID="$VALID$p
"
  else
    [ -n "$REJECTED" ] || REJECTED="$p"
  fi
done <<EOF
$CANDIDATES
EOF

# ---- 3. the hooks/** trigger, ahead of the config read. It needs neither
# sourceGlobs nor jq, and testing it afterwards would let a consumer repo with
# no driver.json - or a jq-less host - degrade a hook change to `standard`,
# which is the one downgrade this trigger exists to make impossible.
while IFS= read -r p; do
  case "$p" in hooks/*) emit 'deep' "hooks:$p" ;; esac
done <<EOF
$VALID
EOF

# ---- 4. sourceGlobs, read the way
# `scripts/build-file-index.sh (sourceGlobs: read from cwd)` reads it, over the
# same transitional legacy-path fallback every other profile reader honors
# (`docs/profile-schema.md (Transitional root read)`). Without it a repo still on
# the legacy layout degrades to `standard` and loses the new-file and twin
# triggers, the one downgrade the hooks trigger above cannot catch.
# tr -d '\r' guards against a Windows jq build emitting CRLF.
command -v jq >/dev/null 2>&1 || emit 'standard' 'no-jq'
PROF="$ROOT/.milestone-config/driver.json"
[ -r "$PROF" ] || PROF="$ROOT/milestone-driver.json"
[ -r "$PROF" ] || emit 'standard' 'no-config'
SRC_RE=''
while IFS= read -r g; do
  [ -n "$g" ] || continue
  valid_path "$g" || continue
  [ -n "$SRC_RE" ] && SRC_RE="$SRC_RE|"
  SRC_RE="$SRC_RE$(glob_to_re "$g")"
done <<EOF
$(jq -r '.sourceGlobs[]?' "$PROF" 2>/dev/null | tr -d '\r')
EOF
[ -n "$SRC_RE" ] || emit 'standard' 'no-source-globs'

# ---- 5. the sourceGlobs-scoped deep triggers, most specific signal first.
# Within a trigger the first candidate in git's order wins, which is path order.
SRC="$(printf '%s' "$VALID" | grep -E "^($SRC_RE)\$")"

while IFS= read -r p; do
  [ -n "$p" ] || continue
  in_list "$p" "$NEWSET" && emit 'deep' "new-file:$p"
done <<EOF
$SRC
EOF

while IFS= read -r p; do
  sib=''
  case "$p" in
    *.sh)  sib="${p%.sh}.ps1" ;;
    *.ps1) sib="${p%.ps1}.sh" ;;
    *) continue ;;
  esac
  in_list "$sib" "$VALID" || emit 'deep' "twin:$p"
done <<EOF
$SRC
EOF

# ---- 6. no deep trigger fired. A rejected candidate is read before the
# sourceGlobs verdict: it is the one candidate whose depth is unknown, and it
# is the reason this run cannot claim `shallow`.
[ -n "$REJECTED" ] && emit 'standard' "rejected-path:$REJECTED"
[ -n "$SRC" ] && emit 'standard'
emit 'shallow'
