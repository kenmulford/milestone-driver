#!/usr/bin/env bash
# milestone-driver — code-review-gate (Claude PreToolUse: Bash,
# if: Bash(gh pr create *) / Bash(gh pr merge *)).
#
# Deterministic backstop for solve-issue's self-policed review-before-commit
# rule: checks for a literal, ANCHORED `## Code Review` heading before a PR
# is created or merged, and blocks when it's missing (docs/profile-schema.md's
# enforcement table — the plugin previously shipped no PreToolUse hook for
# code review at all; this is the fifth gate, alongside force-subagent,
# tests-green, no-push, no-pr-to-protected, no-bom).
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

# ---- gh pr create -----------------------------------------------------------
if [ "$is_create" = "1" ]; then
  # Exemption: --base/-B <protectedBranch> — single-token regex is fine here
  # (branch names never contain spaces), mirrors no-pr-to-protected.sh:36-38.
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
  if [ "$has_body" = "1" ] && heading_match "$cmd"; then exit 0; fi
  if [ "$have_file_content" = "1" ] && heading_match "$file_content"; then exit 0; fi

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

  heading_match "$pr_body" && exit 0
  deny "the PR body is missing the required '$heading' section. Add one before merging the PR,"
fi

exit 0
