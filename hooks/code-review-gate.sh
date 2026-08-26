#!/usr/bin/env bash
# milestone-driver — code-review-gate (Claude PreToolUse: Bash,
# if: Bash(gh pr create *) / Bash(gh pr merge *)).
#
# Deterministic backstop for solve-issue's self-policed review-before-commit
# rule: checks for a literal, ANCHORED `## Code Review` heading before a PR
# is created or merged, and blocks when it's missing (docs/profile-schema.md's
# enforcement table — the plugin previously shipped no PreToolUse hook for
# code review at all; this is the sixth gate, alongside force-subagent,
# no-bom, tests-green, no-push, no-pr-to-protected).
#
# create: detects a --body/-b or --body-file/-F SIGNAL (presence only — NOT a
# precisely delimited value) and checks the heading against the WIDEST
# available surface: the entire decoded command string for an inline
# --body/-b, and the referenced file's full content for --body-file/-F. This
# is a deliberate re-bias toward fail-open (issue #289 review round 2): an
# earlier version tried to precisely EXTRACT the --body value via quote-matched
# capture, but a body containing an escaped quote, or this repo's own
# `--body "$(cat <<'EOF' ... EOF)"` heredoc-in-command-substitution pattern
# with any quote before the heading, truncated the captured value early and
# produced a false BLOCK on the repo's own documented PR shape. Checking the
# wider surface instead accepts a vanishingly unlikely contrived false ALLOW
# (some other flag's value coincidentally containing the heading) in exchange
# for never false-blocking a real PR body — see tests/code-review-gate.cases.tsv
# create_escaped_quote_before_heading / create_heredoc_pattern.
# merge: `gh pr merge` has its own -b/--body/-F flags, but those set the
# MERGE COMMIT message, not the PR body — every real invocation in this repo
# (skills/solve-issue/SKILL.md, skills/solve-milestone/SKILL.md,
# .project/conventions.md) is a bare `gh pr merge [<n>] --squash
# --delete-branch` with no body flag at all. So the merge path always fetches
# the PR's own body via `gh pr view` instead of parsing the merge command.
#
# Heading match is ANCHORED, not a bare substring: `## Code Review` must be
# followed by a non-alphanumeric character or end-of-string, so "## Code
# Reviewer says LGTM" does NOT satisfy the gate.
#
# Verdict parse (issue #604): the heading alone never proved a review ran, so
# the gate also reads the `/code-review run:` value. Accepted: `yes`,
# `deferred (<reason>)`, `n/a - <reason>`. `no`, an unrecognized value, an
# empty value, and a missing slot all DENY -- a body defect, like the
# empty-PR-body deny above, not one of the environment fail-opens below.
# The verdict search is SCOPED to a heading span, because the wide surface
# would otherwise read an incidental `/code-review run:` in prose ABOVE the
# section (a PR describing this gate) as the verdict and false-deny. The span
# is chosen by walking the anchored heading matches LAST TO FIRST and taking
# the first whose text CONTAINS the slot. Anchoring on the last match alone
# false-blocked two real shapes: a findings line citing this file's own
# heading-variable anchor, which quotes the heading text verbatim, and a
# --title carrying the heading after the body on the command line. Requiring the
# heading to BEGIN A LINE was rejected instead: on the inline --body surface
# the heading is preceded by the shell's opening quote on the same line, so
# that rule blocks the repo's most common PR shape outright. The heading
# search itself stays unscoped.
# This is NOT the rejected quote-matched extraction: there is no section-end
# boundary and no attempt to delimit the value -- the verdict is the first
# whitespace-delimited token on the slot's own line, with ONE surrounding
# `"`/`'` stripped per side, since the wide surface glues the command's closing
# quote to a value that ends the body. That strip is bounded in the direction
# that matters: no accepted value contains a quote, so it can never turn a
# rejected token into an accepted one, and a self-quoted `'yes'` ending a body
# still denies.
# EVERY slot in the span is read, not just the first: a wave or milestone PR
# body carries ONE heading with one `### #<n>` block per issue
# (`skills/output-style.md (Wave PR body)`), so a `no` under the second issue
# must deny even when the first reads `yes`.
#
# Exemption: a command targeting protectedBranch (create's --base/-B, or a
# merge whose fetched baseRefName is protectedBranch) is exempt — Ken's manual
# release-PR flow must never fight this gate.
#
# Deny: exit 2 + stderr. Requires jq (to decode the PreToolUse JSON and read
# the profile). Escape: CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1.
# Fail-open: missing jq/gh, unparsed stdin, an unreadable --body-file, or a
# failed `gh pr view` all exit 0 — a hook that crashes is a hook that (silently)
# allows, so every unexpected condition here falls through to allow, not deny.

[ "${CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE:-}" = "1" ] && exit 0

input="$(cat)"
[ -z "$input" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

is_create=0; is_merge=0
[[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+create ]] && is_create=1
[[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+merge ]] && is_merge=1
[ "$is_create" = "0" ] && [ "$is_merge" = "0" ] && exit 0

project_dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$project_dir" ] && project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="${project_dir//\\//}"
profile="$project_dir/.milestone-config/driver.json"
[ -f "$profile" ] || profile="$project_dir/milestone-driver.json"
protected=""
if [ -f "$profile" ]; then
  protected="$(jq -r '.protectedBranch // empty' "$profile" 2>/dev/null)"
  protected="${protected%$'\r'}"
fi

heading='## Code Review'
runslot='/code-review run:'

deny() {
  echo "milestone-driver: $1 or set CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1 to override." >&2
  exit 2
}

# heading_match <text> — true iff <text> contains an ANCHORED `## Code
# Review` (not immediately followed by a letter/digit, so "## Code Reviewer"
# does not match; end-of-string also satisfies the anchor).
heading_match() {
  [[ "$1" =~ "$heading"([^A-Za-z0-9]|$) ]]
}

# verdict_span <text>: walking the ANCHORED heading matches LAST TO FIRST,
# the first span that holds a `/code-review run:` slot; returns 1 when none
# does. Requiring the slot is what stops a LATER mention of the heading (a
# findings line citing it, a --title after the body) stealing the span.
verdict_span() {
  local rest="$1" i
  local spans; spans=()
  while [[ "$rest" == *"$heading"* ]]; do
    rest="${rest#*"$heading"}"
    [[ "$rest" =~ ^[A-Za-z0-9] ]] || spans+=("$rest")
  done
  i=$(( ${#spans[@]} - 1 ))
  while [ "$i" -ge 0 ]; do
    case "${spans[$i]}" in
      *"$runslot"*) printf '%s' "${spans[$i]}"; return 0 ;;
    esac
    i=$((i - 1))
  done
  return 1
}

# verdict_token <after>: first whitespace-delimited token on <after>'s FIRST
# line, unwrapped of one surrounding quote character per side.
verdict_token() {
  local line="${1%%$'\n'*}" tok=""
  line="${line%$'\r'}"
  [[ "$line" =~ ^[[:space:]]*([^[:space:]]+) ]] && tok="${BASH_REMATCH[1]}"
  tok="${tok#[\"\']}"
  tok="${tok%[\"\']}"
  printf '%s' "$tok"
}

# check_verdict <surface> <action>: reads EVERY slot in the span and denies on
# the first one not accepted; never returns on deny.
check_verdict() {
  local span rest tok
  if ! span="$(verdict_span "$1")"; then
    deny "the PR body's '$heading' section has no '$runslot' line, so no review verdict was recorded. Add one reading yes, deferred (<reason>), or n/a - <reason> before $2,"
  fi
  rest="$span"
  while [[ "$rest" == *"$runslot"* ]]; do
    rest="${rest#*"$runslot"}"
    tok="$(verdict_token "$rest")"
    [ -z "$tok" ] && deny "the PR body's '$runslot' line has an empty value, so no review verdict was recorded. Set it to yes, deferred (<reason>), or n/a - <reason> before $2,"
    case "$tok" in
      yes|deferred|n/a) ;;
      *) deny "the PR body records '$runslot $tok', which is not an accepted verdict. Set it to yes, deferred (<reason>), or n/a - <reason> before $2," ;;
    esac
  done
  return 0
}

# ---- gh pr create -----------------------------------------------------------
if [ "$is_create" = "1" ]; then
  # Exemption: --base/-B <protectedBranch> — single-token regex is fine here
  # (branch names never contain spaces), mirrors hooks/no-pr-to-protected.sh (--base[=[:space:]]+).
  if [ -n "$protected" ] && [[ "$cmd" =~ (--base[=[:space:]]+|-B[[:space:]]+)\"?\'?([^[:space:]\"\']+) ]]; then
    [ "${BASH_REMATCH[2]}" = "$protected" ] && exit 0
  fi

  # Presence-only signal detection (NOT value extraction — see header note).
  has_body=0; has_file=0
  [[ "$cmd" =~ (^|[[:space:]])(--body|-b)([=[:space:]]|$) ]] && has_body=1
  [[ "$cmd" =~ (^|[[:space:]])(--body-file|-F)([=[:space:]]|$) ]] && has_file=1

  if [ "$has_body" = "0" ] && [ "$has_file" = "0" ]; then
    deny "gh pr create has no --body/--body-file argument, so the required '$heading' section can't be verified. Add a PR body containing that section,"
  fi

  # --body-file/-F: the PATH itself is a simple single token (mirrors the
  # --base extraction above), so quote-matching it carries none of the
  # multi-word/multi-line truncation risk the inline --body value did.
  have_file_content=0
  file_content=""
  if [ "$has_file" = "1" ]; then
    path_val=""
    if [[ "$cmd" =~ (--body-file[=[:space:]]+|-F[[:space:]]+)\"?\'?([^[:space:]\"\']+) ]]; then
      path_val="${BASH_REMATCH[2]}"
    fi
    [ -z "$path_val" ] && exit 0   # fail-open: flag present but no parseable path
    case "$path_val" in
      /*) bf="$path_val" ;;
      *) bf="$project_dir/$path_val" ;;
    esac
    if [ -r "$bf" ]; then
      file_content="$(cat "$bf" 2>/dev/null)"
      have_file_content=1
    else
      exit 0   # fail-open: --body-file referenced but unreadable
    fi
  fi

  # Wide-surface check: the whole command string for inline --body/-b (never
  # a narrowly extracted substring — see header note), the whole file content
  # for --body-file/-F. Either surface matching is enough to allow.
  if [ "$has_body" = "1" ] && heading_match "$cmd"; then
    check_verdict "$cmd" "opening the PR"; exit 0
  fi
  if [ "$have_file_content" = "1" ] && heading_match "$file_content"; then
    check_verdict "$file_content" "opening the PR"; exit 0
  fi

  deny "the PR body is missing the required '$heading' section. Add one before opening the PR,"
fi

# ---- gh pr merge --------------------------------------------------------------
if [ "$is_merge" = "1" ]; then
  command -v gh >/dev/null 2>&1 || exit 0

  pr_arg=""
  if [[ "$cmd" =~ pr[[:space:]]+merge[[:space:]]+([^-[:space:]][^[:space:]]*) ]]; then
    pr_arg="${BASH_REMATCH[1]}"
  fi

  if [ -n "$pr_arg" ]; then
    view_json="$(gh pr view "$pr_arg" --json body,baseRefName 2>/dev/null)"
  else
    view_json="$(gh pr view --json body,baseRefName 2>/dev/null)"
  fi
  rc=$?
  [ "$rc" -ne 0 ] && exit 0
  [ -z "$view_json" ] && exit 0

  pr_body="$(printf '%s' "$view_json" | jq -r '.body // empty' 2>/dev/null)"
  pr_base="$(printf '%s' "$view_json" | jq -r '.baseRefName // empty' 2>/dev/null)"
  pr_base="${pr_base%$'\r'}"

  [ -n "$protected" ] && [ "$pr_base" = "$protected" ] && exit 0

  if [ -z "$pr_body" ]; then
    deny "the PR's body (fetched via gh pr view) is empty, so the required '$heading' section can't be verified. Add the section to the PR body,"
  fi

  if heading_match "$pr_body"; then
    check_verdict "$pr_body" "merging the PR"; exit 0
  fi
  deny "the PR body is missing the required '$heading' section. Add one before merging the PR,"
fi

exit 0
