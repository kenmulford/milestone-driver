#!/usr/bin/env bash
# milestone-driver - code-review-gate (Claude PreToolUse: Bash,
# if: Bash(gh pr create *) / Bash(gh pr merge *)).
#
# Deterministic backstop for solve-issue's self-policed review-before-commit
# rule: checks for a literal, ANCHORED `## Code Review` heading before a PR
# is created or merged, and blocks when it's missing (docs/profile-schema.md's
# enforcement table - the plugin previously shipped no PreToolUse hook for
# code review at all; this is the sixth gate, alongside force-subagent,
# no-bom, tests-green, no-push, no-pr-to-protected).
#
# create: detects a --body/-b or --body-file/-F SIGNAL (presence only - NOT a
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
# for never false-blocking a real PR body - see tests/code-review-gate.cases.tsv
# create_escaped_quote_before_heading / create_heredoc_pattern.
# merge: the driver's own squash merges (skills/solve-issue/SKILL.md,
# skills/solve-milestone/*, .project/conventions.md) pass --subject and --body;
# the release and back-merge rituals do not, merging with a bare --merge
# (docs/consumer-setup.md). Both flags set the MERGE COMMIT message, never the
# PR body, so the merge path fetches the PR's own body via `gh pr view` instead
# of parsing the merge command.
#
# Heading match is ANCHORED, not a bare substring: `## Code Review` must open
# a section (below) and be followed by a non-alphanumeric character or
# end-of-string, so "## Code Reviewer says LGTM" does NOT satisfy the gate.
#
# Verdict parse (issue #604): the heading alone never proved a review ran, so
# the gate also reads the `/code-review run:` value. Accepted: `yes` and
# `n/a - <reason>`, the latter only for a PR carrying no sourceGlobs change.
# `no`, an unrecognized value, an empty value, and a missing slot all DENY -- a
# body defect, like the empty-PR-body deny above, not one of the environment
# fail-opens below. `deferred` was accepted until the v1.24.0 simplify pass and
# is not: omitting `/code-review` parks the issue `blocked` and a parked issue
# opens no PR (`skills/solve-issue/SKILL.md (treat the omission as a park trigger)`),
# so no legitimate PR body could ever carry it, and accepting it left a
# one-word bypass of the gate that the verdict parse exists to close.
# Sections (milestone #54): the verdict and finding checks read EVERY anchored
# section, so an earlier section's `no` or open finding cannot hide behind a
# later one. A section opens on a line beginning with the heading, or where an
# inline --body/-b value opens with it (on that surface the shell's opening
# quote precedes the heading on its line), and runs to the next line beginning
# `## `; `###` sub-entries stay in. A mid-line mention (prose, a finding citing
# this file's heading variable, a --title) opens none, so an incidental
# `/code-review run:` or arrow outside a section is never read. The heading
# presence check is the same rule.
# This is NOT the rejected quote-matched extraction: no attempt is made to
# delimit the value -- the verdict is the first
# whitespace-delimited token on the slot's own line, with ONE surrounding
# `"`/`'` stripped per side, since the wide surface glues the command's closing
# quote to a value that ends the body. That strip is bounded in the direction
# that matters: no accepted value contains a quote, so it can never turn a
# rejected token into an accepted one, and a self-quoted `'yes'` ending a body
# still denies.
# EVERY slot is read, not just the first: a wave or milestone PR
# body carries ONE heading with one `### #<n>` block per issue
# (`skills/output-style.md (Wave PR body)`), so a `no` under the second issue
# must deny even when the first reads `yes`.
# Finding scan (issue #804): once every verdict slot passes, every section line
# is scanned. A finding line
# starts, after whitespace, one optional `- `, `* ` or `<digits>. ` and one
# optional `**`, with `[Critical]`,
# `[Important]` or `[Minor]`; an unprefixed nested list item (indented) carrying
# the arrow counts as Important (`skills/review-depth.md`), so a top-level
# `- Version: a → b` is none. A Critical or Important
# line denies unless the text after its LAST arrow, cut at its first quote
# (the wide surface glues the closing quote and later flags to the last body
# line) and trimmed, is `re-dispatched and resolved` followed by end of line,
# `.`, a space or `(`; the reason quotes the
# first offender in document order. A `[Minor]` line passes whatever its
# disposition, since the gate holds no build profile.
#
# Exemption: a command targeting protectedBranch (create's --base/-B, or a
# merge whose fetched baseRefName is protectedBranch) is exempt - Ken's manual
# release-PR flow must never fight this gate.
#
# Deny: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON). Requires jq (to decode the PreToolUse JSON and read
# the profile). Escape: CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1.
# Fail-open: missing jq/gh, unparsed stdin, an unreadable --body-file, or a
# failed `gh pr view` all exit 0 - a hook that crashes is a hook that (silently)
# allows, so every unexpected condition here falls through to allow, not deny.

[ "${CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE:-}" = "1" ] && exit 0

input="$(cat)"
hook_dir="${BASH_SOURCE[0]%[/\\]*}"; [ "$hook_dir" = "${BASH_SOURCE[0]}" ] && hook_dir=.   # builtin: PATH may lack dirname
. "$hook_dir/hook-deny.sh"
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
re_head='^## Code Review([^A-Za-z0-9]|$)'
re_open="(^|[[:space:]])(--body|-b)[=[:space:]]+[\"']?$heading([^A-Za-z0-9]|\$)"

deny() {
  hook_deny "$input" "milestone-driver: $1 or set CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1 to override."
}

# sections_of <text>: sets secs to every anchored section's lines, joined by
# newlines; returns 1 when <text> holds none. A section opens on a line that
# begins with the heading (not followed by a letter/digit, so "## Code
# Reviewer" opens none), or on the line where an inline --body/-b value opens
# with it, from the heading on; it runs to the next line beginning `## `.
# A global, not stdout: a command substitution would strip trailing newlines.
sections_of() {
  local rest="$1" line on=0 pre
  secs=""
  while :; do
    line="${rest%%$'\n'*}"
    if [[ $line =~ $re_head ]]; then
      on=1
    elif [[ $line =~ $re_open ]]; then
      pre="${line%%"${BASH_REMATCH[0]}"*}"
      line="${line:${#pre}}"; line="$heading${line#*"$heading"}"; on=1
    else
      case "$line" in "## "*) on=0 ;; esac
    fi
    [ "$on" = 1 ] && secs="$secs$line"$'\n'
    [[ "$rest" == *$'\n'* ]] || break
    rest="${rest#*$'\n'}"
  done
  [ -n "$secs" ]
}

# heading_match <text>: true iff <text> opens at least one section.
heading_match() { sections_of "$1"; }

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

# check_findings <surface> <action>: the finding scan the header describes,
# over every section of <surface>; never returns on deny. No here-string or
# heredoc: both need a writable TMPDIR on bash 3.2.
check_findings() {
  local rest line t d mk ind fnd disp arrow=$'\xe2\x86\x92' want='re-dispatched and resolved'
  sections_of "$1" || return 0
  rest="$secs"
  while [ -n "$rest" ]; do
    line="${rest%%$'\n'*}"
    rest="${rest#*$'\n'}"
    ind=0; case "$line" in [[:space:]]*) ind=1 ;; esac
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    t="$line"; mk=0; fnd=0; d="${t%%[!0-9]*}"
    case "$t" in
      "- "*|"* "*) mk=1; t="${t#??}" ;;
      *) [ -n "$d" ] && [ "${t:${#d}:2}" = ". " ] && { mk=1; t="${t:${#d}+2}"; } ;;
    esac
    t="${t#\*\*}"
    case "$t" in
      "[Minor]"*) ;;
      "[Critical]"*|"[Important]"*) fnd=1 ;;
      *) [ "$mk" = 1 ] && [ "$ind" = 1 ] && [[ "$t" == *"$arrow"* ]] && fnd=1 ;;
    esac
    if [ "$fnd" = 1 ]; then
      disp=""
      [[ "$line" == *"$arrow"* ]] && disp="${line##*"$arrow"}"
      disp="${disp%%[\"\']*}"
      disp="${disp#"${disp%%[![:space:]]*}"}"
      disp="${disp%"${disp##*[![:space:]]}"}"
      case "$disp" in
        "$want"|"$want."*|"$want "*|"$want("*) ;;
        *) deny "the PR body's '$heading' section has a Critical or Important finding whose disposition is not '$want': $line. Record it as $want before $2," ;;
      esac
    fi
  done
  return 0
}

# check_verdict <surface> <action>: reads EVERY slot in every section and
# denies on the first one not accepted, then scans the findings; never returns
# on deny.
check_verdict() {
  local rest tok
  sections_of "$1"
  case "$secs" in
    *"$runslot"*) ;;
    *) deny "the PR body's '$heading' section has no '$runslot' line, so no review verdict was recorded. Add one reading yes or n/a - <reason> before $2," ;;
  esac
  rest="$secs"
  while [[ "$rest" == *"$runslot"* ]]; do
    rest="${rest#*"$runslot"}"
    tok="$(verdict_token "$rest")"
    [ -z "$tok" ] && deny "the PR body's '$runslot' line has an empty value, so no review verdict was recorded. Set it to yes or n/a - <reason> before $2,"
    case "$tok" in
      yes|n/a) ;;
      *) deny "the PR body records '$runslot $tok', which is not an accepted verdict. Set it to yes or n/a - <reason> before $2," ;;
    esac
  done
  check_findings "$1" "$2"
}

# ---- gh pr create -----------------------------------------------------------
if [ "$is_create" = "1" ]; then
  # Exemption: --base/-B <protectedBranch> - single-token regex is fine here
  # (branch names never contain spaces), mirrors hooks/no-pr-to-protected.sh (--base[=[:space:]]+).
  if [ -n "$protected" ] && [[ "$cmd" =~ (--base[=[:space:]]+|-B[[:space:]]+)\"?\'?([^[:space:]\"\']+) ]]; then
    [ "${BASH_REMATCH[2]}" = "$protected" ] && exit 0
  fi

  # Presence-only signal detection (NOT value extraction - see header note).
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
    double_file_pattern='(--body-file[=[:space:]]+|-F[[:space:]]+)"([^"]*)"'
    single_file_pattern="(--body-file[=[:space:]]+|-F[[:space:]]+)'([^']*)'"
    bare_file_pattern='(--body-file[=[:space:]]+|-F[[:space:]]+)([^[:space:]]+)'
    if [[ "$cmd" =~ $double_file_pattern ]]; then
      path_val="${BASH_REMATCH[2]}"
    elif [[ "$cmd" =~ $single_file_pattern ]]; then
      path_val="${BASH_REMATCH[2]}"
    elif [[ "$cmd" =~ $bare_file_pattern ]]; then
      path_val="${BASH_REMATCH[2]}"
    fi
    [ -z "$path_val" ] && exit 0   # fail-open: flag present but no parseable path
    drive_rooted=0
    case "$path_val" in \\*) drive_rooted=1 ;; esac
    path_val="${path_val//\\//}"
    if [ "$drive_rooted" = 1 ]; then
      case "$path_val" in
        //*) ;;
        /*) case "$project_dir" in [A-Za-z]:/*) path_val="${project_dir:0:2}$path_val" ;; esac ;;
      esac
    fi
    case "$path_val" in
      /*|[A-Za-z]:/*) bf="$path_val" ;;
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
  # a narrowly extracted substring - see header note), the whole file content
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
