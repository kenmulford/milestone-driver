#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for classify-delta.sh (issues #476, #625).
#
# Each TSV row builds a throwaway git repo: commit `base`, take the PRE-fix
# snapshot through the classifier's own `--snapshot` mode, write `work`, add an
# untracked file when the row names one, apply the row's git `ops`, then run the
# classifier as `<repo-root> <pre-tree>` and assert stdout + stderr exactly.
# Every row therefore exercises the snapshot path as well as the classifier. A
# row can name several files, separated by `|` in the path/base/work columns.
# Bespoke cases follow the table for the inputs a TSV cell cannot hold: a
# snapshot taken anywhere but the commit, an unresolvable pre-tree, a staged new
# file, a staged edit, a rename, an ignored file (tracked and untracked), a
# linked worktree, a binary change, a missing trailing newline, a bare repo, a
# non-repo root, a same-size edit the stat cache calls clean, and the three
# assertions about `--snapshot` itself.
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

pass=0; fail=0; skipped=0
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
# update-index wrote, which is the one path that behaves the same on Windows -
# and the snapshot sees it because it seeds its index from the real one.
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

# take_snapshot <repo> - the pre-fix tree hash, through the classifier's own
# --snapshot mode, so the path the orchestrator calls is the path under test.
take_snapshot() { "$BASH_BIN" "$SCRIPT" --snapshot "$1" 2>/dev/null; }

# run_case <name> <repo> <pre> <want_out> <want_err> - the literal @NONE@ as
# <pre> passes no second argument at all, which is the missing-pre-tree input.
run_case() {
  local name="$1" repo="$2" pre="$3" want_out="$4" want_err="$5" out err rc
  if [ "$pre" = '@NONE@' ]; then
    out="$("$BASH_BIN" "$SCRIPT" "$repo" 2>"$ERRFILE")"; rc=$?
  else
    out="$("$BASH_BIN" "$SCRIPT" "$repo" "$pre" 2>"$ERRFILE")"; rc=$?
  fi
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
  pre="$(take_snapshot "$repo")"
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

  run_case "$name" "$repo" "$pre" "$want_out" "$want_err"
done < "$CASES"

if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES - this run tested nothing" >&2
  exit 1
fi

# ---- bespoke: THE case this classifier exists for (#625). The issue diff is
# uncommitted when /code-review runs, so HEAD is not the pre-fix state: the
# orchestrator snapshots the tree it is about to hand the implementer, and the
# comment-only fix on top is what gets classified. Against HEAD this reads
# `code:a.sh` - the whole issue diff - and the branch is unreachable.
b0="$TMP/b-uncommitted-issue"; mkrepo "$b0"
printf '%s\n' 'exit 0' > "$b0/a.sh"; commit_all "$b0" 'base'
printf '%s\n' 'exit 1' > "$b0/a.sh"
pre0="$(take_snapshot "$b0")"
printf '%s\n' '# note' >> "$b0/a.sh"
run_case 'uncommitted_issue_diff_then_comment_fix' "$b0" "$pre0" 'comment-only' ''

# ---- bespoke: the same tree, classified against HEAD's tree instead. The
# snapshot is the whole difference between this verdict and the one above.
b0b="$TMP/b-snapshot-at-head"; mkrepo "$b0b"
printf '%s\n' 'exit 0' > "$b0b/a.sh"; commit_all "$b0b" 'base'
printf '%s\n' 'exit 1' > "$b0b/a.sh"
pre0b="$(git -C "$b0b" rev-parse 'HEAD^{tree}' 2>/dev/null)"
printf '%s\n' '# note' >> "$b0b/a.sh"
run_case 'snapshot_at_head_sees_issue_diff' "$b0b" "$pre0b" 'code-changed' 'code:a.sh'

# ---- bespoke: the pre-tree argument itself. A caller that forgot it, one that
# passed a name no object answers to, and one that passed a real object of the
# wrong type all fail safe rather than classifying something else.
b8="$TMP/b-no-pre"; mkrepo "$b8"
printf '%s\n' '# c' > "$b8/a.sh"; commit_all "$b8" 'base'
run_case 'missing_pre' "$b8" '@NONE@' 'code-changed' 'no-pre'

b9="$TMP/b-garbage-pre"; mkrepo "$b9"
printf '%s\n' '# c' > "$b9/a.sh"; commit_all "$b9" 'base'
run_case 'garbage_pre' "$b9" 'deadbeef' 'code-changed' 'bad-pre:deadbeef'

b10="$TMP/b-blob-pre"; mkrepo "$b10"
printf '%s\n' '# c' > "$b10/a.sh"; commit_all "$b10" 'base'
blob="$(git -C "$b10" hash-object -w a.sh 2>/dev/null)"
run_case 'blob_pre_is_not_a_tree' "$b10" "$blob" 'code-changed' "bad-pre:$blob"

# ---- bespoke: a new file, staged or not. The delta is a tree pair now, so a
# file absent from the pre-tree reports as `added:` before its content is read
# at all: existence is behavior, the same call `deleted:` makes. Its content is
# not a second case, because the reason fires before any content line is read.
b1="$TMP/b-staged-new"; mkrepo "$b1"
printf '%s\n' '# base' > "$b1/a.sh"; commit_all "$b1" 'base'
pre1="$(take_snapshot "$b1")"
printf '%s\n' '# a new note' > "$b1/new.sh"; git -C "$b1" add new.sh >/dev/null 2>&1
run_case 'staged_new_file_all_comment' "$b1" "$pre1" 'code-changed' 'added:new.sh'

# ---- bespoke: a staged comment edit. The snapshot reads the working tree
# through a throwaway index, so a tree left staged by a denied commit at
# tests-green exit 2 is seen exactly like an unstaged one.
b3="$TMP/b-staged-edit"; mkrepo "$b3"
printf '%s\n' '# old' 'exit 0' > "$b3/a.sh"; commit_all "$b3" 'base'
pre3="$(take_snapshot "$b3")"
printf '%s\n' '# new' 'exit 0' > "$b3/a.sh"; git -C "$b3" add a.sh >/dev/null 2>&1
run_case 'staged_comment_edit' "$b3" "$pre3" 'comment-only' ''

# ---- bespoke: a rename with no content change. `similarity index` /
# `rename from` / `rename to` are skipped as headers, leaving zero content
# lines, and a path change is not a comment edit.
b4="$TMP/b-rename"; mkrepo "$b4"
printf '%s\n' '# one' '# two' > "$b4/a.sh"; commit_all "$b4" 'base'
pre4="$(take_snapshot "$b4")"
git -C "$b4" mv a.sh b.sh >/dev/null 2>&1
run_case 'rename_only' "$b4" "$pre4" 'code-changed' 'no-content:a.sh'

# ---- bespoke: a binary change. Git emits "Binary files ... differ" with no
# readable line, on a file whose extension IS mapped, so only the named header
# shape can catch it.
b5="$TMP/b-binary"; mkrepo "$b5"
printf '%s\n' '<!-- c -->' > "$b5/a.md"; commit_all "$b5" 'base'
pre5="$(take_snapshot "$b5")"
printf 'a\000b\000c' > "$b5/a.md"
run_case 'binary_change' "$b5" "$pre5" 'code-changed' 'binary'

# ---- bespoke: "\ No newline at end of file" is a header, not a content line.
# Dropping the trailing newline off a reworded comment emits it twice.
b6="$TMP/b-nonl"; mkrepo "$b6"
printf 'exit 0\n# old\n' > "$b6/a.sh"; commit_all "$b6" 'base'
pre6="$(take_snapshot "$b6")"
printf 'exit 0\n# new' > "$b6/a.sh"
run_case 'no_newline_at_eof' "$b6" "$pre6" 'comment-only' ''

# ---- bespoke: a root that is not a git repo at all. Fail safe, never crash.
# The reason is `bad-pre:` and not `no-delta`: the object check runs before the
# post snapshot, and outside a repo no object resolves - not even the empty tree
# every repo holds. EMPTY_TREE is git's constant for it.
EMPTY_TREE='4b825dc642cb6eb9a060e54bf8d69288fbee4904'
b7="$TMP/b-notrepo"; mkdir -p "$b7"
run_case 'not_a_git_repo' "$b7" "$EMPTY_TREE" 'code-changed' "bad-pre:$EMPTY_TREE"

# ---- bespoke: a TRACKED file that .gitignore also names. `git add -A` into an
# EMPTY index skips it - ignore rules apply to an untracked path, and to git a
# path with no index entry is untracked - so a code change in it would be in
# neither tree and the delta would read comment-only. Seeding the throwaway
# index from the real one keeps the entry, and the file stays tracked.
b15="$TMP/b-tracked-ignored"; mkrepo "$b15"
printf '%s\n' 'exit 0' > "$b15/gen.sh"
printf '%s\n' '# old' > "$b15/a.sh"
printf '%s\n' 'gen.sh' > "$b15/.gitignore"
git -C "$b15" add -A >/dev/null 2>&1
git -C "$b15" add -f gen.sh >/dev/null 2>&1
git -C "$b15" commit -q -m 'base' >/dev/null 2>&1
pre15="$(take_snapshot "$b15")"
printf '%s\n' 'exit 99' > "$b15/gen.sh"
printf '%s\n' '# new' > "$b15/a.sh"
run_case 'tracked_ignored_file_code_change' "$b15" "$pre15" 'code-changed' 'code:gen.sh'

# ---- bespoke: the control, and the other half of the rule. An UNTRACKED
# ignored file is in neither tree however it changes, so it never reaches the
# delta and the comment reword beside it still classifies comment-only.
b16="$TMP/b-untracked-ignored"; mkrepo "$b16"
printf '%s\n' '# old' > "$b16/a.sh"
printf '%s\n' 'junk.log' > "$b16/.gitignore"
commit_all "$b16" 'base'
printf '%s\n' 'noise' > "$b16/junk.log"
pre16="$(take_snapshot "$b16")"
printf '%s\n' '# new' > "$b16/a.sh"
printf '%s\n' 'more noise' >> "$b16/junk.log"
run_case 'untracked_ignored_file_is_not_in_the_delta' "$b16" "$pre16" 'comment-only' ''

# ---- bespoke: the same tracked-and-ignored change inside a LINKED worktree,
# where the index is not <root>/.git/index at all but
# .git/worktrees/<name>/index. `git rev-parse --git-path index` is what finds
# it; a hardcoded .git/index would seed nothing there and the file would go
# invisible again - in exactly the place the driver builds in parallel mode.
b17="$TMP/b-worktree"; mkrepo "$b17"
printf '%s\n' 'exit 0' > "$b17/gen.sh"
printf '%s\n' '# old' > "$b17/a.sh"
printf '%s\n' 'gen.sh' > "$b17/.gitignore"
git -C "$b17" add -A >/dev/null 2>&1
git -C "$b17" add -f gen.sh >/dev/null 2>&1
git -C "$b17" commit -q -m 'base' >/dev/null 2>&1
wt17="$TMP/b-worktree-linked"
git -C "$b17" worktree add -q "$wt17" -b wtb >/dev/null 2>&1
pre17="$(take_snapshot "$wt17")"
printf '%s\n' 'exit 99' > "$wt17/gen.sh"
printf '%s\n' '# new' > "$wt17/a.sh"
run_case 'tracked_ignored_in_linked_worktree' "$wt17" "$pre17" 'code-changed' 'code:gen.sh'

# ---- bespoke: the classify-mode no-delta branch, which needs a root whose
# objects resolve but whose working tree does not exist. A BARE repo is exactly
# that: `cat-file -t` answers `tree` for the clone's own HEAD tree, and
# `add -A` fails with "this operation must be run in a work tree".
b18="$TMP/b-bare-src"; mkrepo "$b18"
printf '%s\n' '# c' > "$b18/a.sh"; commit_all "$b18" 'base'
tree18="$(git -C "$b18" rev-parse 'HEAD^{tree}' 2>/dev/null)"
bare18="$TMP/b-bare.git"
git clone -q --bare "$b18" "$bare18" >/dev/null 2>&1
run_case 'bare_repo_post_snapshot_fails' "$bare18" "$tree18" 'code-changed' 'no-delta'

# ---- bespoke: a same-size edit that every stat field calls clean. This is
# PINNED, not raced: the indexed mtime, the file's mtime after the edit, and the
# index file's own mtime are one fixed instant in the past, and the repo trusts
# mtime and size alone (`core.checkStat minimal`, `core.trustctime false` - both
# supported settings for filesystems whose other fields move). Git's only
# remaining reason to re-read the content is then the racily-clean rule, which
# fires exactly when the seed copy carries the real index's mtime. Take the -p
# off `cp` in the script and this case reads `empty-delta` on every run, because
# the post tree keeps the stale blob.
RACY_STAMP='202001020304.05'
b19="$TMP/b-racy"; mkrepo "$b19"
git -C "$b19" config core.trustctime false
git -C "$b19" config core.checkStat minimal
printf '%s\n' '# c' 'exit 0' > "$b19/a.sh"
touch -t "$RACY_STAMP" "$b19/a.sh"
commit_all "$b19" 'base'
pre19="$(git -C "$b19" rev-parse 'HEAD^{tree}' 2>/dev/null)"
printf '%s\n' '# c' 'exit 1' > "$b19/a.sh"
touch -t "$RACY_STAMP" "$b19/a.sh"
touch -t "$RACY_STAMP" "$b19/.git/index"
run_case 'racily_clean_same_size_edit' "$b19" "$pre19" 'code-changed' 'code:a.sh'

# ---- bespoke: --snapshot itself, the two properties the callers depend on.
# It must not disturb the real index (the orchestrator runs it on a tree the
# implementer is mid-way through), and it must be LOUD when it cannot write a
# tree - a classify-mode degrade is safe because it resolves to code-changed,
# but a silently-empty pre-tree hash is not: it would arrive as `no-pre` on the
# next call and hide the failure behind a plausible verdict.
b13="$TMP/b-snapshot-index"; mkrepo "$b13"
printf '%s\n' '# base' > "$b13/a.sh"; commit_all "$b13" 'base'
printf '%s\n' '# edited' > "$b13/a.sh"
printf '%s\n' '# untracked' > "$b13/new.sh"
before="$(git -C "$b13" status --porcelain 2>/dev/null)"
snap_out="$(take_snapshot "$b13")"
after="$(git -C "$b13" status --porcelain 2>/dev/null)"
snap_type="$(git -C "$b13" cat-file -t "$snap_out" 2>/dev/null)"
if [ "$snap_type" = 'tree' ] && [ "$before" = "$after" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-38s snapshot=[%s] type=[%s] before=[%s] after=[%s]\n' \
    'snapshot_leaves_index_untouched' "$snap_out" "$snap_type" "$before" "$after" >&2
fi

b14="$TMP/b-snapshot-notrepo"; mkdir -p "$b14"
snap_out="$("$BASH_BIN" "$SCRIPT" --snapshot "$b14" 2>"$ERRFILE")"; snap_rc=$?
snap_err="$(cat "$ERRFILE")"
if [ "$snap_rc" -ne 0 ] && [ -z "$snap_out" ] && [ "$snap_err" = 'snapshot-failed' ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  printf 'FAIL %-38s rc=%s out=[%s] err=[%s]\n' \
    'snapshot_failure_is_loud' "$snap_rc" "$snap_out" "$snap_err" >&2
fi

# ---- bespoke: a real index that exists and cannot be read. The seed IS the
# snapshot's correctness, so this fails loud rather than falling back to the
# empty index that loses a tracked-and-ignored file. chmod 000 is the
# deterministic way to make the copy fail - for any user but root, which is why
# the case checks first and counts itself skipped rather than failing there.
b20="$TMP/b-unreadable-seed"; mkrepo "$b20"
printf '%s\n' '# c' > "$b20/a.sh"; commit_all "$b20" 'base'
chmod 000 "$b20/.git/index" 2>/dev/null
if [ -r "$b20/.git/index" ]; then
  skipped=$((skipped + 1))
  chmod 600 "$b20/.git/index" 2>/dev/null
  printf 'SKIP %-38s the index stayed readable after chmod 000 (running as root?)\n' \
    'unreadable_seed_is_loud' >&2
else
  # The temp dir the snapshot makes is named cd-snap-*, so a leak is countable.
  snap_root="${TMPDIR:-/tmp}"
  before_dirs="$(ls -d "$snap_root"/cd-snap-* 2>/dev/null | wc -l | tr -d ' ')"
  snap_out="$("$BASH_BIN" "$SCRIPT" --snapshot "$b20" 2>"$ERRFILE")"; snap_rc=$?
  snap_err="$(cat "$ERRFILE")"
  chmod 600 "$b20/.git/index" 2>/dev/null
  after_dirs="$(ls -d "$snap_root"/cd-snap-* 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$snap_rc" -ne 0 ] && [ -z "$snap_out" ] && [ "$snap_err" = 'snapshot-failed' ] \
     && [ "$before_dirs" = "$after_dirs" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-38s rc=%s out=[%s] err=[%s] tempdirs %s->%s\n' \
      'unreadable_seed_is_loud' "$snap_rc" "$snap_out" "$snap_err" \
      "$before_dirs" "$after_dirs" >&2
  fi
fi

echo "classify-delta.sh: $pass passed, $fail failed, $skipped skipped (parsed $case_count TSV cases + 19 bespoke)"
[ "$fail" -eq 0 ]
