#!/usr/bin/env bash
# milestone-driver - comment-only delta classifier (issues #476, #625).
#
# Answers ONE question for `skills/solve-issue/SKILL.md (After a fix, before
# committing)`: is the delta between a pre-fix tree and the tree now comment
# text only, or did it change code? The answer picks the post-fix branch, so it
# must be mechanical. It used to be prose rules an agent applied by eye, and
# that prose failed two review rounds on input shapes it had not enumerated.
# This script IS the enumeration.
#
# Usage:   classify-delta.sh --snapshot [REPO_ROOT]
#          classify-delta.sh [REPO_ROOT] [PRE_TREE]
#   --snapshot  write the working tree to a tree object and print its hash. The
#               caller takes this immediately BEFORE dispatching the fix and
#               passes the hash back as PRE_TREE once the fix returns.
#   REPO_ROOT   path to a checked-out repo root (default: CWD).
#   PRE_TREE    the hash a --snapshot call printed before the fix.
#
# Output, snapshot mode: the tree hash on stdout, newline-terminated, exit 0.
# On any failure: nothing on stdout, `snapshot-failed` on stderr, exit 1. This
# is the one LOUD path here, deliberately - a classify degrade is safe because
# it resolves to code-changed, but a silently empty hash would come back on the
# next call as `no-pre` and hide the failure behind a plausible verdict.
#
# Output (stdout), classify mode, exactly one line, newline-terminated:
#   comment-only    every changed line is comment text, in a mapped language
#   code-changed    anything else
# Output (stderr), only when the verdict is code-changed, exactly one token:
#   no-pre               no PRE_TREE was given
#   bad-pre:<tree>       PRE_TREE names no object, or names a non-tree
#   no-delta             the post-fix snapshot failed, or git could not diff
#   empty-delta          the delta is empty
#   binary               a "Binary files ... differ" hunk
#   unmapped-ext:<path>  a changed file whose extension is not in the mapping
#   added:<path>         a file the pre-tree does not hold (see "A FILE THE
#                        PRE-TREE DOES NOT HOLD" below)
#   deleted:<path>       a file the post-tree does not hold
#   rename:<path>        a file whose path changed, at its new path
#   mode:<path>          an "old mode" / "new mode" header
#   heredoc:<path>       a .sh file carrying a heredoc, so a column-0 comment
#                        line in it may be payload, not a comment
#   directive:<path>     a machine-read directive behind a comment prefix
#   code:<path>          a changed line that is not comment text
#   no-content:<path>    a file whose diff block carries zero content lines
# In classify mode Exit is ALWAYS 0. The verdict is the output, not the exit
# code, so a caller never has to tell "code-changed" apart from "the script
# broke".
#
# The safe direction is code-changed. Every uncertainty resolves that way,
# because code-changed only costs a re-run of the unit suite and /code-review,
# while a wrong comment-only skips both.
#
# WHAT THE DELTA IS. Two tree objects: the PRE_TREE a --snapshot call wrote
# before the fix was dispatched, and a POST tree this run writes the same way.
# NOT `git diff HEAD`, which this script read until #625: in the driver's
# procedure the issue's own diff is still uncommitted while the review and its
# fix happen, so HEAD is the state before the ISSUE and never the state before
# the FIX. The delta was then the whole issue plus the fix, and `comment-only`
# was reachable only when the entire issue was comment text.
#
# A snapshot is `GIT_INDEX_FILE=<temp> git add -A` then `git write-tree`, over a
# temp index SEEDED from the repo's real one, so it sees staged, unstaged, and
# untracked work alike. The real index is only ever READ, so this is safe to run
# against a tree an agent is mid-way through. One consequence is not a read:
# under `core.splitIndex` git resolves the shared index against the REAL gitdir,
# so writing the seeded temp index can leave a new `sharedindex.*` file there
# (measured 2026-08-27). The real index itself still parses and still describes
# the same state.
#
# THE SEED IS LOAD-BEARING, not an optimization. `.gitignore` decides only what
# an UNTRACKED path contributes; a TRACKED file the ignore rules also name stays
# tracked, and its changes stay visible. Into an EMPTY index that is not what
# happens: git reads a path with no index entry as untracked, `add -A` then
# honors the ignore rule and drops it, and a code change in a tracked-and-
# ignored file (a generated script, a committed .env) would be missing from BOTH
# trees and classify comment-only (verified 2026-08-27). The seed keeps the
# entry, so the file stays tracked in the tree this writes.
#
# THE SEED MUST KEEP THE REAL INDEX'S MTIME, which is why the copy is `cp -p`
# (the pwsh leg restamps the copy). Git decides whether to trust an entry's
# cached stat by comparing that entry's mtime against the mtime of the INDEX
# FILE it was read from: an entry at or after it is "racily clean" and its
# content is re-read. A copy stamped `now` makes every entry look safely old, so
# `add -A` trusts the stat - and a same-size edit made in the same second as the
# indexed write then has identical stat fields and is skipped, putting the
# unchanged blob in the tree. Measured at 2 misses in 200 runs with a plain
# copy, 0 in 200 with -p (2026-08-27). `git status` and `git diff HEAD` are not
# exposed to it because they read the real index at its own mtime.
#
# Three hazards. The temp index must sit OUTSIDE the repo, or `add -A` records
# the index's own lock file as a tree entry. Its path must not exist yet,
# because git rejects a zero-length index file ("index file smaller than
# expected") - exactly what a plain `mktemp` leaves behind - so the temp is a
# DIRECTORY and the index is a name inside it. And the real index is located
# with `git rev-parse --git-path index`, never a hardcoded `.git/index`: a
# linked worktree keeps its index under `.git/worktrees/<name>/`, which is
# precisely where the driver builds in parallel mode.
#
# A mode change is then whatever the seeded index plus `add -A` produce: an
# index-only `git update-index --chmod` is visible because the seed carries that
# entry, and a bare on-disk chmod only where `core.filemode` is true.
#
# Plain `git diff <tree>` was rejected: against a working tree it reports a path
# the tree holds and the working tree leaves untracked as a DELETION (verified
# 2026-08-26), so every untracked file in the pre-tree would read as `deleted:`.
#
# A FILE THE PRE-TREE DOES NOT HOLD IS `added:<path>`, whatever its content, and
# that fires before the extension gate and before any content line is read.
# Existence is behavior - a sourced, required, or CI-referenced path appearing
# changes what runs - and it is the symmetric twin of `deleted:`. The rule this
# replaces was a separate `ls-files --others` pre-scan emitting `untracked:`,
# which `git diff HEAD` needed because it could not see an untracked file at
# all. A tree pair sees one as an ordinary add, so both that pre-scan and that
# token are retired, and a staged new file no longer classifies differently from
# an unstaged one.
#
# HOW THE DIFF IS PARSED. A unified diff at -U0 has no context lines, so inside
# a hunk every line starting with + or - is content and everything else is a
# header. Outside a hunk, "--- a/f" and "+++ b/f" are file headers. That
# distinction is POSITIONAL, tracked by the in_hunk flag, and it has to be:
# a markdown source line "---" arrives as "+---" and a source line "+++ TOML"
# arrives as "++++ TOML". Reading either as a file header would drop a real
# content line. Every other header shape (index, new file mode, deleted file
# mode, similarity index, rename from/to, copy from/to, dissimilarity index,
# and "\ No newline at end of file") falls through to the catch-all and is
# skipped. Three shapes are called out by name instead, because each carries a
# real change with no readable content line: "Binary files ... differ",
# "old mode", and "new mode".
#
# CONTENT IS COUNTED PER FILE, not across the delta. Each "diff --git" opens a
# block and the next one closes it; a block that closes with zero content lines
# changed without a readable line (a 100%-similar rename, a mode-only change)
# and takes the safe branch. A global count would let a comment reword in one
# file pay for a silently moved file in another.
#
# A PATH CHANGE IS NOT A COMMENT EDIT, and neither is a deletion. The "+++"
# path is compared against the "---" path: a differing pair is a rename carrying
# an edit, "+++ /dev/null" is a deletion, and a "---" side of "/dev/null" is the
# addition the paragraph above resolves. A file's existence is behavior, because
# a sourced, required, or CI-referenced path appearing or disappearing changes
# what runs.
#
# THE MARKER IS STRIPPED BEFORE THE PREFIX TEST, exactly one character. A
# removed SQL comment "-- one" arrives as "--- one"; stripping one - leaves the
# comment intact, and the positional parse above is what keeps the real
# "--- a/f" header out of this path.
#
# COMMENT TOKENS MUST SIT AT COLUMN 0 of the source line. An indented comment
# classifies as code-changed. That is deliberate: an indented "#" is
# indistinguishable from a heredoc or printf payload that emits #-prefixed
# text, and payload text is program output, not a comment.
#
# A COLUMN-0 HEREDOC BODY IS PAYLOAD TOO, and column 0 alone cannot tell it
# apart from a comment: "cat <<EOF" then "# one" is program output. Reading the
# line's position against the file's heredoc regions would need the pre-image
# and the post-image both, so this resolves the blunt way instead: when a .sh
# file carries "<<" anywhere, every column-0 comment line in it takes the safe
# branch. Over-inclusion costs a suite re-run; the miss skips it entirely.
#
# A BLOCK COMMENT THAT CLOSES MID-LINE takes the safe branch when anything but
# whitespace follows the closing token. "/* n */ Environment.Exit(1);" opens
# with a comment prefix and runs code, and the same shape is reachable for
# "#>" in .ps1, "-->" in .md, and "*/" in .js/.ts/.go/.sql. Only a line opening
# with the block's OWN open or close token is scanned, so a line comment that
# merely mentions the token ("// see */ below") is left alone.
#
# A BLANK LINE IS NOT COMMENT TEXT. It carries no comment token, and inside a
# multi-line string literal it changes the value, so it takes the safe branch.
#
# PREFIXES ARE PER-EXTENSION, never a flat cross-language set: "#count = 0" at
# column 0 of a .js or .ts file is a private class field, not a comment.
set -u
# Byte-indexed string ops and byte-range bracket expressions, so this leg and
# the pwsh twin's ordinal/ASCII model agree on every boundary test
# (`scripts/extract-version.sh (Force a deterministic byte model)`).
export LC_ALL=C

if [ "${1:-}" = '--snapshot' ]; then
  MODE='snapshot'; ROOT="${2:-$PWD}"; PRE=''
else
  MODE='classify'; ROOT="${1:-$PWD}"; PRE="${2:-}"
fi
ROOT="${ROOT%/}"

# emit <verdict> [reason]
emit() {
  printf '%s\n' "$1"
  [ -n "${2:-}" ] && printf '%s' "$2" >&2
  exit 0
}

# prefixes_for <lowercased-ext> -> prints one comment prefix per line, or
# returns 1 when the extension is not mapped.
prefixes_for() {
  case "$1" in
    sh|py|rb)    printf '%s\n' '#' ;;
    ps1)         printf '%s\n' '#' '<#' '#>' ;;
    md)          printf '%s\n' '<!--' '-->' ;;
    cs|js|ts|go) printf '%s\n' '//' '/*' '*/' ;;
    sql)         printf '%s\n' '--' '/*' '*/' ;;
    *) return 1 ;;
  esac
}

# block_tokens_for <lowercased-ext> -> prints "<open> <close>" for the
# extensions that have a block comment form, or returns 1. Both tokens can open
# a line: "<# c #> code" and "#> code" are the same defect.
block_tokens_for() {
  case "$1" in
    ps1)             printf '%s %s\n' '<#' '#>' ;;
    md)              printf '%s %s\n' '<!--' '-->' ;;
    cs|js|ts|go|sql) printf '%s %s\n' '/*' '*/' ;;
    *) return 1 ;;
  esac
}

# ext_of <path> -> prints the lowercased extension, or returns 1 when the
# basename carries none. bash-3.2-safe: `tr`, not ${var,,}.
ext_of() {
  local base="${1##*/}" ext
  case "$base" in
    *.*) ext="${base##*.}" ;;
    *) return 1 ;;
  esac
  [ -n "$ext" ] || return 1
  printf '%s' "$ext" | tr 'A-Z' 'a-z'
}

# strip_ab <path> -> drops the diff's a/ or b/ prefix.
strip_ab() {
  case "$1" in
    a/*|b/*) printf '%s' "${1#?/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# is_directive <src> -> 0 when the line opens with a machine-read directive.
#
# These sit behind a comment prefix but a toolchain reads them, so changing one
# changes behavior. The list is checked BEFORE the comment test and WITHOUT
# regard to the file's extension: a #pragma is not a comment prefix in .cs at
# all, and a stray match in another language only pushes toward the safe branch.
#
# The boundary rule is uniform. When a directive's last character is
# alphanumeric, the next source character must be absent or a non-word
# character, so "#if DEBUG" matches while a prose comment "#iffy" does not.
# When it is not alphanumeric (#!, # type:, // @ts-, // eslint-), the directive
# is its own boundary and a plain prefix test is enough.
is_directive() {
  local s="$1" d last rest
  for d in '#!' '# shellcheck' '# frozen_string_literal' '# type:' '# noqa' \
           '// @ts-' '// eslint-' '//go:build' '#pragma' '#if' '#region' '#endif'; do
    case "$s" in
      "$d"*)
        last="${d#"${d%?}"}"
        case "$last" in
          [0-9A-Za-z])
            rest="${s#"$d"}"
            case "$rest" in
              ''|[!0-9A-Za-z_]*) return 0 ;;
            esac
            ;;
          *) return 0 ;;
        esac
        ;;
    esac
  done
  return 1
}

# is_comment <src> -> 0 when the line opens with one of CUR_PREFIXES at column 0.
is_comment() {
  local s="$1" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$s" in "$p"*) return 0 ;; esac
  done <<EOF
$CUR_PREFIXES
EOF
  return 1
}

# closes_block_then_code <src> -> 0 when the line opens with the file's block
# open or close token, that block closes before end of line, and something
# other than whitespace follows the closing token.
closes_block_then_code() {
  local s="$1" rest
  [ -n "$CUR_BLOCK_CLOSE" ] || return 1
  case "$s" in
    "$CUR_BLOCK_OPEN"*|"$CUR_BLOCK_CLOSE"*) ;;
    *) return 1 ;;
  esac
  case "$s" in
    *"$CUR_BLOCK_CLOSE"*) rest="${s#*"$CUR_BLOCK_CLOSE"}" ;;
    *) return 1 ;;
  esac
  case "$rest" in
    *[![:space:]]*) return 0 ;;
  esac
  return 1
}

# has_heredoc <path> -> 0 when the working-tree file carries "<<" anywhere, or
# cannot be read at all. Deliberately blunt: "<<" also matches a left shift and
# a comment that names the operator, and both resolve to code-changed, which is
# the safe direction. An unreadable file is an uncertainty, so it resolves the
# same way.
has_heredoc() {
  local f="$ROOT/$1"
  [ -r "$f" ] || return 0
  grep -q '<<' "$f" 2>/dev/null
}

# snapshot <root> - prints the tree hash for that root's working tree, or
# returns 1 having printed nothing. The temp index is a name inside a temp
# DIRECTORY, seeded from the real index, for the three hazards the header
# records; the index and its lock are removed by name whichever way this goes.
# A seed that cannot be copied returns 1 rather than falling back to an empty
# index, which would silently reinstate the tracked-and-ignored blind spot.
snapshot() {
  local root="$1" dir idx real src tmproot tree='' seeded=1
  # Named, not the default template: a leaked snapshot dir has to be findable
  # (the suite counts cd-snap-* before and after), and the pwsh twin names its
  # own the same way.
  tmproot="${TMPDIR:-/tmp}"; tmproot="${tmproot%/}"
  dir="$(mktemp -d "$tmproot/cd-snap-XXXXXX" 2>/dev/null)" || return 1
  idx="$dir/index"
  real="$(git -C "$root" rev-parse --git-path index 2>/dev/null)" || real=''
  if [ -n "$real" ]; then
    # --git-path prints a path relative to <root> unless it is already absolute,
    # which it is for a linked worktree. The drive-letter patterns are the
    # Windows spelling of absolute, where LC_ALL=C keeps the range byte-exact.
    case "$real" in
      /*|[A-Za-z]:/*|[A-Za-z]:\\*) src="$real" ;;
      *) src="$root/$real" ;;
    esac
    # -p, not a bare cp: the copy must carry the real index's mtime, or git
    # trusts a stat cache it would otherwise have re-checked (see THE SEED MUST
    # KEEP THE REAL INDEX'S MTIME).
    [ -f "$src" ] && { cp -p "$src" "$idx" 2>/dev/null || seeded=0; }
  fi
  if [ "$seeded" = '1' ] && GIT_INDEX_FILE="$idx" git -C "$root" add -A >/dev/null 2>&1; then
    tree="$(GIT_INDEX_FILE="$idx" git -C "$root" write-tree 2>/dev/null)" || tree=''
  fi
  # Unconditional: git leaves an index.lock behind on some failure paths, and a
  # by-name removal would then leave the directory standing forever.
  rm -rf "$dir"
  [ -n "$tree" ] || return 1
  printf '%s' "$tree"
}

if [ "$MODE" = 'snapshot' ]; then
  snapshot_tree="$(snapshot "$ROOT")" || { printf '%s' 'snapshot-failed' >&2; exit 1; }
  printf '%s\n' "$snapshot_tree"
  exit 0
fi

# ---- 1. the tree pair, pre-fix first.
[ -n "$PRE" ] || emit 'code-changed' 'no-pre'
# The type test rejects a name no object answers to and a real object of the
# wrong kind alike. Outside a repo it fails too, which is why a non-repo root
# reports bad-pre and never reaches the snapshot below.
[ "$(git -C "$ROOT" cat-file -t "$PRE" 2>/dev/null)" = 'tree' ] \
  || emit 'code-changed' "bad-pre:$PRE"
POST="$(snapshot "$ROOT")" || emit 'code-changed' 'no-delta'

# ---- 2. the delta.
# The -c and -- flags pin the output shape against any repo/user config that
# would reshape it: quoted non-ASCII paths, a dropped a//b/ prefix, color
# codes, an external diff driver, or a textconv filter. -M forces rename
# detection ON, so a rename reports as a rename (no content lines, hence
# code-changed) instead of decomposing into a delete plus an add whose
# all-comment content would read as comment-only. -r is redundant beside -p,
# which recurses on its own, and is written anyway: diff-tree does NOT recurse
# by default, and a reader should not have to know which flag implies it.
delta="$(git -C "$ROOT" -c core.quotePath=false --no-pager diff-tree -r -p -U0 \
  -M --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ \
  "$PRE" "$POST" 2>/dev/null)" || emit 'code-changed' 'no-delta'
[ -n "$delta" ] || emit 'code-changed' 'empty-delta'

# ---- 3. walk it.
in_hunk=0
a_path=''
cur_path=''
cur_mapped=0
cur_ext=''
cur_heredoc=''
CUR_PREFIXES=''
CUR_BLOCK_OPEN=''
CUR_BLOCK_CLOSE=''
block_open=0
block_path=''
block_content=0
verdict=''
reason=''

# set_file <path> - registers the file the following hunks belong to and
# resolves its comment prefixes once.
set_file() {
  cur_path="$1"
  cur_heredoc=''
  CUR_BLOCK_OPEN=''
  CUR_BLOCK_CLOSE=''
  local bt=''
  cur_ext="$(ext_of "$cur_path")" || cur_ext=''
  if [ -n "$cur_ext" ] && CUR_PREFIXES="$(prefixes_for "$cur_ext")"; then
    cur_mapped=1
    if bt="$(block_tokens_for "$cur_ext")"; then
      CUR_BLOCK_OPEN="${bt%% *}"
      CUR_BLOCK_CLOSE="${bt##* }"
    fi
  else
    cur_mapped=0
    CUR_PREFIXES=''
  fi
}

# Process substitution, not a pipeline: the loop must run in THIS shell so the
# verdict it sets survives the loop.
while IFS= read -r line; do
  # Content first, and only inside a hunk. This ordering is what keeps a
  # markdown "+---" or "++++ TOML" source line from being read as a file header.
  if [ "$in_hunk" = '1' ]; then
    case "$line" in
      '+'*|'-'*)
        src="${line:1}"
        block_content=$((block_content + 1))
        if is_directive "$src"; then
          verdict='code-changed'; reason="directive:$cur_path"; break
        fi
        if ! is_comment "$src"; then
          verdict='code-changed'; reason="code:$cur_path"; break
        fi
        if closes_block_then_code "$src"; then
          verdict='code-changed'; reason="code:$cur_path"; break
        fi
        # Resolved once per file, and only on a line that would otherwise pass
        # as a comment, so a real code change keeps the more precise reason.
        if [ "$cur_ext" = 'sh' ]; then
          if [ -z "$cur_heredoc" ]; then
            if has_heredoc "$cur_path"; then cur_heredoc='yes'; else cur_heredoc='no'; fi
          fi
          if [ "$cur_heredoc" = 'yes' ]; then
            verdict='code-changed'; reason="heredoc:$cur_path"; break
          fi
        fi
        continue
        ;;
    esac
  fi
  case "$line" in
    'diff --git '*)
      # Close the block this header ends before opening the next one.
      if [ "$block_open" = '1' ] && [ "$block_content" -eq 0 ]; then
        verdict='code-changed'; reason="no-content:$block_path"; break
      fi
      in_hunk=0; a_path=''; cur_path=''; cur_mapped=0; cur_ext=''; cur_heredoc=''
      CUR_PREFIXES=''; CUR_BLOCK_OPEN=''; CUR_BLOCK_CLOSE=''
      # Best-effort path for the reasons that fire before "+++" registers one.
      # A path holding a space truncates here; the verdict does not depend on
      # it, only the token does.
      g="${line#diff --git }"
      block_path="$(strip_ab "${g%% *}")"
      block_open=1; block_content=0 ;;
    'Binary files '*)
      verdict='code-changed'; reason='binary'; break ;;
    'old mode '*|'new mode '*)
      verdict='code-changed'; reason="mode:$block_path"; break ;;
    '--- '*)
      p="${line#--- }"
      if [ "$p" = '/dev/null' ]; then a_path=''; else a_path="$(strip_ab "$p")"; fi ;;
    '+++ '*)
      p="${line#+++ }"
      if [ "$p" = '/dev/null' ]; then
        verdict='code-changed'; reason="deleted:$a_path"; break
      fi
      new_path="$(strip_ab "$p")"
      if [ -n "$a_path" ] && [ "$a_path" != "$new_path" ]; then
        verdict='code-changed'; reason="rename:$new_path"; break
      fi
      if [ -z "$a_path" ]; then
        verdict='code-changed'; reason="added:$new_path"; break
      fi
      set_file "$new_path"
      # The extension gate fires at registration, not at the first content
      # line, so an unmapped file that changed with no readable content still
      # reports why it is code-changed.
      if [ "$cur_mapped" != '1' ]; then
        verdict='code-changed'; reason="unmapped-ext:$cur_path"; break
      fi ;;
    '@@'*)
      in_hunk=1 ;;
    *) : ;;
  esac
done < <(printf '%s\n' "$delta")

[ -n "$verdict" ] && emit "$verdict" "$reason"
# The first line is an UNREACHABLE fail-safe and is kept as one: `diff-tree -r
# -p` opens every non-empty output with a `diff --git` header (verified against
# a mode-only change, an empty-file add, and a symlink typechange in both
# directions), so no input arrives here with no block open. One ever doing so
# would mean the delta was not parsed at all, where the safe answer is
# code-changed - and that is why its token is absent from the list above, which
# documents only what a caller can actually be handed.
[ "$block_open" = '1' ] || emit 'code-changed' 'no-content'
[ "$block_content" -eq 0 ] && emit 'code-changed' "no-content:$block_path"
emit 'comment-only'
