#!/usr/bin/env bash
# milestone-driver - golden-matrix runner for code-review-gate.sh (issue #289).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../hooks/code-review-gate.sh"
CASES="$HERE/code-review-gate.cases.tsv"
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 3; }
[ -f "$SCRIPT" ] || { echo "FATAL: missing $SCRIPT" >&2; exit 3; }
BASH_BIN="$(command -v bash)"

pass=0; fail=0
TMP="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/crg.$$")"; mkdir -p "$TMP"
ERRFILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/crg_err.$$")"
cleanup() { rm -rf "$TMP" "$ERRFILE"; }
trap cleanup EXIT

TAB=$'\t'
EXPECT_COLS=11
split_tab() {
  local rest="$1$TAB"
  cols=()
  while [ -n "$rest" ]; do cols+=("${rest%%"$TAB"*}"); rest="${rest#*"$TAB"}"; done
}

unescape() { printf '%b' "$1"; }

make_gh_stub() {
  local mode="$1" json="$2"
  local dir; dir="$(mktemp -d)"
  case "$mode" in
    NOGH)
      ln -sf "$(command -v jq)" "$dir/jq"
      ln -sf "$(command -v cat)" "$dir/cat"
      ;;
    ERROR)
      printf '#!/usr/bin/env bash\nexit 1\n' > "$dir/gh"
      chmod +x "$dir/gh"
      ;;
    OK)
      printf '%s' "$json" > "$dir/view.json"
      {
        printf '#!/usr/bin/env bash\n'
        printf 'if [ "$1" = "pr" ] && [ "$2" = "view" ]; then cat %q; exit 0; fi\n' "$dir/view.json"
        printf 'exit 1\n'
      } > "$dir/gh"
      chmod +x "$dir/gh"
      ;;
  esac
  printf '%s' "$dir"
}

pass_t() { pass=$((pass+1)); }
fail_t() {
  fail=$((fail+1))
  printf 'FAIL %s: rc=%s (want %s) stderr=[%s] (want [%s]) stdout=[%s]\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" >&2
}

case_count=0
while IFS= read -r row || [ -n "$row" ]; do
  case "$row" in ''|\#*) continue;; esac
  row="${row%$'\r'}"
  split_tab "$row"
  if [ "${#cols[@]}" -ne "$EXPECT_COLS" ]; then
    echo "FATAL: row failed to parse (got ${#cols[@]} fields, want $EXPECT_COLS): [$row]" >&2
    exit 1
  fi
  case_count=$((case_count+1))
  name="${cols[0]:-}"; verb="${cols[1]:-}"; command_raw="${cols[2]:-}"
  bodyfile_content="${cols[3]:-}"; gh_mode="${cols[4]:-}"
  gh_view_body="${cols[5]:-}"; gh_view_base="${cols[6]:-}"
  protected="${cols[7]:-main}"; disable_env="${cols[8]:-}"
  want_exit="${cols[9]:-0}"; want_stderr="${cols[10]:-}"

  cmd="$(unescape "$command_raw")"

  if [[ "$cmd" == *"__BODYFILE_REL__"* ]]; then
    rel="${name}-body.md"
    unescape "$bodyfile_content" > "$TMP/$rel"
    cmd="${cmd/__BODYFILE_REL__/$rel}"
  elif [[ "$cmd" == *"__BODYFILE_ABS__"* ]]; then
    abs="$TMP/${name}-body-abs.md"
    unescape "$bodyfile_content" > "$abs"
    cmd="${cmd/__BODYFILE_ABS__/$abs}"
  fi

  mkdir -p "$TMP/.milestone-config"
  jq -n --arg p "$protected" '{protectedBranch:$p}' > "$TMP/.milestone-config/driver.json"

  json_in="$(jq -n --arg cmd "$cmd" --arg cwd "$TMP" '{tool_input:{command:$cmd}, cwd:$cwd}')"

  run_path="$PATH"
  stub_dir=""
  if [ "$verb" = "merge" ] && [ -n "$gh_mode" ]; then
    view_json="$(jq -n --arg b "$(unescape "$gh_view_body")" --arg base "$gh_view_base" '{body:$b, baseRefName:$base}')"
    stub_dir="$(make_gh_stub "$gh_mode" "$view_json")"
    if [ "$gh_mode" = "NOGH" ]; then run_path="$stub_dir"; else run_path="$stub_dir:$PATH"; fi
  fi

  if [ "$disable_env" = "1" ]; then
    out="$(printf '%s' "$json_in" | PATH="$run_path" CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1 "$BASH_BIN" "$SCRIPT" 2>"$ERRFILE")"
  else
    out="$(printf '%s' "$json_in" | PATH="$run_path" "$BASH_BIN" "$SCRIPT" 2>"$ERRFILE")"
  fi
  rc=$?
  err="$(cat "$ERRFILE")"

  [ -n "$stub_dir" ] && rm -rf "$stub_dir"

  want_err="$(unescape "$want_stderr")"
  if [ "$rc" -eq "$want_exit" ] && [ "$err" = "$want_err" ] && [ -z "$out" ]; then
    pass_t
  else
    fail_t "$name" "$rc" "$want_exit" "$err" "$want_err" "$out"
  fi
done < "$CASES"

if [ "$case_count" -eq 0 ]; then
  echo "FATAL: parsed 0 cases from $CASES - this run tested nothing" >&2
  exit 1
fi

# ---- bespoke case: missing jq -> fail open (needs a PATH with no jq at all,
NOJQ_DIR="$(mktemp -d)"
ln -sf "$(command -v cat)" "$NOJQ_DIR/cat"
raw_json='{"tool_input":{"command":"gh pr create --base develop --title \"x\""},"cwd":"'"$TMP"'"}'
out="$(printf '%s' "$raw_json" | PATH="$NOJQ_DIR" "$BASH_BIN" "$SCRIPT" 2>"$ERRFILE")"; rc=$?
err="$(cat "$ERRFILE")"
rm -rf "$NOJQ_DIR"
if [ "$rc" -eq 0 ] && [ -z "$err" ] && [ -z "$out" ]; then pass_t; else
  fail_t "missing_jq_failopen" "$rc" "0" "$err" "" "$out"; fi

echo "code-review-gate.sh: $pass passed, $fail failed (parsed $case_count TSV cases + 1 bespoke)"
[ "$fail" -eq 0 ]
