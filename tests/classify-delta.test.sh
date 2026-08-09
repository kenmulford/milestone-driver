#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for classify-delta.sh (issue #476).
#
# Each TSV row builds a throwaway git repo: commit `base`, write `work`, add an
# untracked file when the row names one, apply the row's git `ops`, then run the
# classifier against the repo root and assert stdout + stderr exactly. A row can
# name several files, separated by `|` in the path/base/work columns. Bespoke
# cases follow the table for the inputs a TSV cell cannot hold: a staged new
# file, a staged edit, a rename, a binary change, a missing trailing newline,
# and a non-repo root.
#
# bash-3.2-safe (no mapfile, no `local -n`, no ${var,,}), matching
# `tests/code-review-gate.test.sh (bash-3.2-safe TAB split)`.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/classify-delta.sh"
CASES="$HERE/classify-delta.cases.tsv"
command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 3; }
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
BASH_BIN="$(command -v bash)"

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/cd.$$")"; mkdir -p "$TMP"
ERRFILE="$TMP/err"
trap 'rm -rf "$TMP"' EXIT

TAB=$'\t'
EXPECT_COLS=8
# Sets the GLOBAL `cols` array; preserves empty fields, which `IFS=$'\t' read`
# collapses.
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}

# Sets the GLOBAL `parts` array from a `|`-separated cell, same empty-field
# handling as split_tab.
split_pipe() {
  local rest="$1|"
  parts=()
  while [ -n "$rest" ]; do parts+=("${rest%%|*}"); rest="${rest#*|}"; done
}

unescape() { printf '%b' "$1"; }

# mkrepo <dir> - a throwaway repo pinned against the developer's global git
# config: no hooks (a global core.hooksPath would otherwise run on the fixture),
# no signing, no CRLF translation, and a fixed identity so `commit` never
# prompts. core.filemode is off so the `chmodx` op reads the index mode git
# update-index wrote, which is the one path that behaves the same on Windows.
mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q >/dev/null 2>&1
  git -C "$d" config core.hooksPath "$d/.git/no-such-hooks"
  git -C "$d" config commit.gpgsign false
  git -C "$d" config core.autocrlf false
  git -C "$d" config core.safecrlf false
  git -C "$d" config core.filemode false
  git -C "$d" config user.email 'tests@milestone-driver.invalid'
  git -C "$d" config user.name 'classify-delta tests'
}

# apply_op <repo> <op> - the row's single git operation, run after `work` lands.
apply_op() {
  local repo="$1" op="$2" rest from to
  case "$op" in
    '-') : ;;
    mv:*)
      rest="${op#mv:}"; from="${rest%%:*}"; to="${rest#*:}"
      git -C "$repo" mv "$from" "$to" >/dev/null 2>&1 ;;
    chmodx:*)
      git -C "$repo" update-index --chmod=+x "${op#chmodx:}" >/dev/null 2>&1 ;;
    *) echo "FATAL: unknown op [$op]" >&2; exit 1 ;;
  esac
}

commit_all() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -q -m "$2" >/dev/null 2>&1; }

# run_case <name> <repo> <want_out> <want_err>
run_case() {
  local name="$1" repo="$2" want_out="$3" want_err="$4" out err rc
  out="$("$BASH_BIN" "$SCRIPT" "$repo" 2>"$ERRFILE")"; rc=$?
  err="$(cat "$ERRFILE")"
  if [ "$rc" -eq 0 ] && [ "$out" = "$want_out" ] && [ "$err" = "$want_err" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-38s rc=%s got[out=%s err=%s] want[out=%s err=%s]\n' \
      "$name" "$rc" "$out" "$err" "$want_out" "$want_err" >&2
  fi
}

case_count=0
while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in ''|\#*) continue;; esac
  row="${row%$'\r'}"
  split_tab "$row"
  # A row that does not parse into exactly EXPECT_COLS fields is a corrupt
  # fixture, not a silently-defaulted pass.
  if [ "${#cols[@]}" -ne "$EXPECT_COLS" ]; then
    echo "FATAL: row failed to parse (got ${#cols[@]} fields, want $EXPECT_COLS): [$row]" >&2
    exit 1
  fi
  case_count=$((case_count + 1))
  name="${cols[0]}"; path="${cols[1]}"; base="${cols[2]}"; work="${cols[3]}"
  untracked="${cols[4]}"; ops="${cols[5]}"; want_out="${cols[6]}"; want_err="${cols[7]}"

  split_pipe "$path"; paths=("${parts[@]}")
  split_pipe "$base"; bases=("${parts[@]}")
  split_pipe "$work"; works=("${parts[@]}")
  if [ "${#bases[@]}" -ne "${#paths[@]}" ] || [ "${#works[@]}" -ne "${#paths[@]}" ]; then
    echo "FATAL: $name has ${#paths[@]} paths but ${#bases[@]} base / ${#works[@]} work values" >&2
    exit 1
  fi

  repo="$TMP/r$case_count"
  mkrepo "$repo"
  i=0
  while [ "$i" -lt "${#paths[@]}" ]; do
    unescape "${bases[$i]}" > "$repo/${paths[$i]}"
    i=$((i + 1))
  done
  commit_all "$repo" 'base'
  i=0
  while [ "$i" -lt "${#paths[@]}" ]; do
    case "${works[$i]}" in
      '=') : ;;
      '@DEL@') rm -f "$repo/${paths[$i]}" ;;
      *) unescape "${works[$i]}" > "$repo/${paths[$i]}" ;;
    esac
    i=$((i + 1))
  done
  [ "$untracked" != '-' ] && printf '%s\n' '# untracked' > "$repo/$untracked"
  apply_op "$repo" "$ops"

  run_case "$name" "$repo" "$want_out" "$want_err"
done < "$CASES"

if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES - this run tested nothing" >&2
  exit 1
fi

# ---- bespoke: a STAGED new file is visible in `git diff HEAD` as a
# "new file mode" header, so it is classified on its content, not treated as
# untracked. This is the pair to untracked_only above: visibility is the rule.
b1="$TMP/b-staged-new"; mkrepo "$b1"
printf '%s\n' '# base' > "$b1/a.sh"; commit_all "$b1" 'base'
printf '%s\n' '# a new note' > "$b1/new.sh"; git -C "$b1" add new.sh >/dev/null 2>&1
run_case 'staged_new_file_all_comment' "$b1" 'comment-only' ''

b2="$TMP/b-staged-new-code"; mkrepo "$b2"
printf '%s\n' '# base' > "$b2/a.sh"; commit_all "$b2" 'base'
printf '%s\n' 'exit 1' > "$b2/new.sh"; git -C "$b2" add new.sh >/dev/null 2>&1
run_case 'staged_new_file_with_code' "$b2" 'code-changed' 'code:new.sh'

# ---- bespoke: a staged comment edit. Bare `git diff -U0` prints nothing once
# the tree is staged (a denied commit at tests-green exit 2 leaves it that
# way); diffing against HEAD still sees it.
b3="$TMP/b-staged-edit"; mkrepo "$b3"
printf '%s\n' '# old' 'exit 0' > "$b3/a.sh"; commit_all "$b3" 'base'
printf '%s\n' '# new' 'exit 0' > "$b3/a.sh"; git -C "$b3" add a.sh >/dev/null 2>&1
run_case 'staged_comment_edit' "$b3" 'comment-only' ''

# ---- bespoke: a rename with no content change. `similarity index` /
# `rename from` / `rename to` are skipped as headers, leaving zero content
# lines, and a path change is not a comment edit.
b4="$TMP/b-rename"; mkrepo "$b4"
printf '%s\n' '# one' '# two' > "$b4/a.sh"; commit_all "$b4" 'base'
git -C "$b4" mv a.sh b.sh >/dev/null 2>&1
run_case 'rename_only' "$b4" 'code-changed' 'no-content:a.sh'

# ---- bespoke: a binary change. Git emits "Binary files ... differ" with no
# readable line, on a file whose extension IS mapped, so only the named header
# shape can catch it.
b5="$TMP/b-binary"; mkrepo "$b5"
printf '%s\n' '<!-- c -->' > "$b5/a.md"; commit_all "$b5" 'base'
printf 'a\000b\000c' > "$b5/a.md"
run_case 'binary_change' "$b5" 'code-changed' 'binary'

# ---- bespoke: "\ No newline at end of file" is a header, not a content line.
# Dropping the trailing newline off a reworded comment emits it twice.
b6="$TMP/b-nonl"; mkrepo "$b6"
printf 'exit 0\n# old\n' > "$b6/a.sh"; commit_all "$b6" 'base'
printf 'exit 0\n# new' > "$b6/a.sh"
run_case 'no_newline_at_eof' "$b6" 'comment-only' ''

# ---- bespoke: a root that is not a git repo at all. Fail safe, never crash.
b7="$TMP/b-notrepo"; mkdir -p "$b7"
run_case 'not_a_git_repo' "$b7" 'code-changed' 'no-delta'

echo "classify-delta.sh: $pass passed, $fail failed (parsed $case_count TSV cases + 7 bespoke)"
[ "$fail" -eq 0 ]
