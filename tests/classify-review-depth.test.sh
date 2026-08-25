#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for classify-review-depth.sh (issue #598).
#
# Each TSV row builds a throwaway git repo: write the row's driver.json and its
# `base` files, commit them, apply the row's working-tree `ops`, then run the
# classifier against the row's run root - the repo root, or the subdirectory an
# `R:` op names - and assert stdout + stderr exactly. Four bespoke cases follow
# the table for the inputs a TSV cell cannot express: a directory that is not a
# repo, a repo with no commit for `HEAD` to name, and a stripped PATH with git
# removed, then with jq removed.
#
# The harness is `tests/classify-delta.test.sh (mkrepo <dir> - a throwaway repo)`,
# not the flat stdin table `tests/extract-version.cases.tsv` drives: this
# classifier's whole input is git state, so a row has to build a repo before it
# can assert anything.
#
# bash-3.2-safe (no mapfile, no `local -n`, no ${var,,}), matching
# `tests/code-review-gate.test.sh (bash-3.2-safe TAB split)`.
set -u
# Byte-indexed string ops, so this leg and the pwsh twin agree on every
# boundary test (`scripts/extract-version.sh (Force a deterministic byte model)`).
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/classify-review-depth.sh"
CASES="$HERE/classify-review-depth.cases.tsv"
command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 3; }
# The script under test reads sourceGlobs with jq, so a jq-less host would turn
# every row into the `no-jq` degrade instead of testing the matrix.
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
BASH_BIN="$(command -v bash)"

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/crd.$$")"; mkdir -p "$TMP"
ERRFILE="$TMP/err"
trap 'rm -r -f "$TMP"' EXIT

TAB=$'\t'
EXPECT_COLS=6
# Sets the GLOBAL `cols` array; preserves empty fields, which `IFS=$'\t' read`
# collapses.
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}

# Sets the GLOBAL `parts` array from a `|`-separated cell.
split_pipe() {
  local rest="$1|"
  parts=()
  while [ -n "$rest" ]; do parts+=("${rest%%|*}"); rest="${rest#*|}"; done
}

# mkrepo <dir> - a throwaway repo pinned against the developer's global git
# config: no hooks (a global core.hooksPath would otherwise run on the fixture),
# no signing, no CRLF translation, and a fixed identity so `commit` never
# prompts. core.quotePath is deliberately left at its default, because the
# classifier has to pin it itself and a pre-pinned fixture would hide that.
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
  git -C "$d" config user.name 'classify-review-depth tests'
}

commit_all() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -q -m "$2" >/dev/null 2>&1; }

# mkfile <repo> <repo-relative path> <content>
mkfile() {
  local f="$1/$2"
  mkdir -p "${f%/*}"
  printf '%s\n' "$3" > "$f"
}

# write_config <repo> <globs cell>. No glob in the table carries a character
# JSON escapes, so the array is assembled by hand rather than through jq.
write_config() {
  local repo="$1" cell="$2" json='' g
  [ "$cell" = '-' ] && return 0
  mkdir -p "$repo/.milestone-config"
  if [ "$cell" = '@EMPTY@' ]; then
    printf '%s\n' '{}' > "$repo/.milestone-config/driver.json"
    return 0
  fi
  # A JSON scalar where the schema says array. Spelled as a sentinel because the
  # cell's `|` split can only ever build an array.
  if [ "$cell" = '@SCALAR@' ]; then
    printf '%s\n' '{"sourceGlobs":"scripts/**"}' > "$repo/.milestone-config/driver.json"
    return 0
  fi
  split_pipe "$cell"
  for g in "${parts[@]}"; do
    [ -n "$json" ] && json="$json,"
    json="$json\"$g\""
  done
  printf '{"sourceGlobs":[%s]}\n' "$json" > "$repo/.milestone-config/driver.json"
}

# root_sub <ops cell> -> the `R:<subdir>` argument, or empty. Read BEFORE the
# repo is populated, because the run root is where driver.json has to land.
# Runs in a subshell at every call site, so clobbering the global `parts` here
# cannot reach the caller's split.
root_sub() {
  local cell="$1" op
  [ "$cell" = '-' ] && return 0
  split_pipe "$cell"
  for op in "${parts[@]}"; do
    case "$op" in R:*) printf '%s' "${op#R:}"; return 0 ;; esac
  done
  return 0
}

# apply_ops <repo> <ops cell>. Paths are relative to the REPO root, never to the
# run root, so a row reads the same whether or not it carries an `R:` op.
apply_ops() {
  local repo="$1" cell="$2" op kind p
  [ "$cell" = '-' ] && return 0
  split_pipe "$cell"
  local ops_list=("${parts[@]}")
  for op in "${ops_list[@]}"; do
    kind="${op%%:*}"; p="${op#*:}"
    case "$kind" in
      M|N) mkfile "$repo" "$p" 'changed' ;;
      E|S) mkfile "$repo" "$p" 'changed'; git -C "$repo" add "$p" >/dev/null 2>&1 ;;
      D)   rm -f "$repo/$p" ;;
      R)   : ;;
      *)   echo "FATAL: unknown op [$op]" >&2; exit 1 ;;
    esac
  done
}

# run_case <name> <repo> <want_out> <want_err> [PATH override]
# BASH_BIN is absolute, so a stripped PATH override still launches the script
# (`tests/code-review-gate.test.sh (restricted PATH)`).
run_case() {
  # ${5-...}, NOT ${5:-...}: the absent-tool cases pass an EMPTY PATH on
  # purpose, and the colon spelling substitutes $PATH right back in.
  local name="$1" repo="$2" want_out="$3" want_err="$4" pth="${5-$PATH}" out err rc
  out="$(PATH="$pth" "$BASH_BIN" "$SCRIPT" "$repo" 2>"$ERRFILE")"; rc=$?
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
  name="${cols[0]}"; globs="${cols[1]}"; base="${cols[2]}"
  ops="${cols[3]}"; want_out="${cols[4]}"; want_err="${cols[5]}"

  repo="$TMP/r$case_count"
  mkrepo "$repo"
  sub="$(root_sub "$ops")"
  runroot="$repo"
  if [ -n "$sub" ]; then runroot="$repo/$sub"; mkdir -p "$runroot"; fi
  write_config "$runroot" "$globs"
  # A committed seed, so HEAD exists even for a row naming no base file.
  mkfile "$repo" 'README.md' 'seed'
  if [ "$base" != '-' ]; then
    split_pipe "$base"
    base_list=("${parts[@]}")
    for bp in "${base_list[@]}"; do mkfile "$repo" "$bp" 'seed'; done
  fi
  commit_all "$repo" 'base'
  apply_ops "$repo" "$ops"

  run_case "$name" "$runroot" "$want_out" "$want_err"
done < "$CASES"

if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES - this run tested nothing" >&2
  exit 1
fi

# ---- bespoke: a root that is not a git repo at all. Fail open to standard,
# never a crash.
b1="$TMP/b-notrepo"; mkdir -p "$b1"
run_case 'not_a_git_repo' "$b1" 'standard' 'no-diff'

# ---- bespoke: an initialized repo with no commit. `git diff HEAD` has no HEAD
# to name and fails, so the candidate set is unreadable even though the tree
# holds files.
b2="$TMP/b-nohead"; mkrepo "$b2"
mkdir -p "$b2/.milestone-config"
printf '%s\n' '{"sourceGlobs":["scripts/**"]}' > "$b2/.milestone-config/driver.json"
mkfile "$b2" 'scripts/a.sh' 'seed'
run_case 'repo_without_commits' "$b2" 'standard' 'no-diff'

# ---- bespoke: git absent from PATH. An empty PATH is enough - every command
# the script reaches before the git probe is a shell builtin.
b3="$TMP/b-nogit"; mkrepo "$b3"
mkfile "$b3" 'scripts/a.sh' 'seed'
commit_all "$b3" 'base'
mkfile "$b3" 'scripts/a.sh' 'changed'
run_case 'git_absent_from_path' "$b3" 'standard' 'no-git' ''

# ---- bespoke: jq absent from PATH, with git still present. Bash-only: the
# pwsh leg reads sourceGlobs with ConvertFrom-Json and has no jq to lose.
# The fixture touches scripts/, never hooks/, because the hooks trigger now
# runs BEFORE the jq probe and would answer `deep` first.
NOJQ_DIR="$TMP/bin-nojq"; mkdir -p "$NOJQ_DIR"
ln -sf "$(command -v git)" "$NOJQ_DIR/git"
b4="$TMP/b-nojq"; mkrepo "$b4"
mkdir -p "$b4/.milestone-config"
printf '%s\n' '{"sourceGlobs":["scripts/**"]}' > "$b4/.milestone-config/driver.json"
mkfile "$b4" 'scripts/a.sh' 'seed'
commit_all "$b4" 'base'
mkfile "$b4" 'scripts/a.sh' 'changed'
run_case 'jq_absent_from_path' "$b4" 'standard' 'no-jq' "$NOJQ_DIR"

echo "classify-review-depth.sh: $pass passed, $fail failed (parsed $case_count TSV cases + 4 bespoke)"
[ "$fail" -eq 0 ]
