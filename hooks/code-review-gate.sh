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
# Sections (milestone #54): the verdict check reads EVERY section, so an
# earlier section's `no` cannot hide behind a later one. A heading opens a
# section at line start after whitespace, or after a `"`, `'` or `$'` opener
# directly following `--body `, `--body=`, `-b ` or a `NAME=` word, since the
# inline surface puts the shell's quote before the heading; a `--title` or
# prose mention opens none, so an incidental `/code-review run:` is never read.
# A section runs to the next line whose text after whitespace begins `## `.
# Every rule skips lines between ``` fences (on the inline surface \`\`\` too),
# and a leading UTF-8 BOM is stripped from a --body-file and the fetched body,
# as PowerShell's reader does. The heading presence check is the same rule.
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
# Finding scan (issue #804): it fails closed, so no body shape can hide a
# finding: once the verdicts pass, it reads every unfenced line of the create
# command and any --body-file, or of the fetched body, ignoring sections. A line
# opening, after whitespace, an optional `- `, `* ` or `<digits>. ` marker and
# `**`, then `[Critical]` or `[Important]`, is a finding, and so is a marked
# line with no severity prefix carrying the arrow (`skills/review-depth.md`),
# a `- Version: a → b` label included: its author writes `to`. It denies unless
# the text after its LAST arrow is `re-dispatched and resolved` alone, with a
# final `.`, or with one ` (...)` holding no parenthesis and closing the line,
# then at most one shell quote, since the wide surface glues the command's
# closing quote to the last body line. The reason quotes the first offender in
# document order. A `[Minor]` line passes, since the gate holds no build
# profile.
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
re_pre="^[[:space:]]*\$|(^|[[:space:]])(--body[ =]|-b |[A-Za-z_][A-Za-z0-9_]*=)(\"|'|\\\$')\$"
re_ok="^re-dispatched and resolved(\\.| \\([^()]*\\))?[[:space:]]*[\"']?\$"
bom=$'\xef\xbb\xbf'

deny() {
  hook_deny "$input" "milestone-driver: $1 or set CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1 to override."
}

# is_fence <lead> <inline>: true iff <lead> opens or closes a ``` fence; the
# inline surface also counts the \`\`\` a double-quoted shell body carries.
is_fence() { [[ "$1" == '```'* ]] || { [ "$2" = 1 ] && [[ "$1" == '\`\`\`'* ]]; }; }

# open_at <line>: sets pre to the text before the first heading on <line>
# that opens a section; returns 1 when none does.
open_at() {
  local s="$1" p=""
  while [[ "$s" == *"$heading"* ]]; do
    p="$p${s%%"$heading"*}"
    s="${s#*"$heading"}"
    if [[ ! "$s" =~ ^[A-Za-z0-9] ]] && [[ "$p" =~ $re_pre ]]; then pre="$p"; return 0; fi
    p="$p$heading"
  done
  return 1
}

# sections_of <text> <inline>: sets secs to every section's unfenced lines
# from the heading on, joined by newlines; returns 1 when <text> holds none.
# A global, not stdout: a command substitution would strip trailing newlines.
sections_of() {
  local rest="$1" line lead on=0 fence=0
  secs=""
  while :; do
    line="${rest%%$'\n'*}"
    lead="${line#"${line%%[![:space:]]*}"}"
    if is_fence "$lead" "$2"; then
      fence=$((1 - fence))
    elif [ "$fence" = 0 ]; then
      if open_at "$line"; then
        line="${line:${#pre}}"; on=1
      else
        case "$lead" in "## "*) on=0 ;; esac
      fi
      [ "$on" = 1 ] && secs="$secs$line"$'\n'
    fi
    [[ "$rest" == *$'\n'* ]] || break
    rest="${rest#*$'\n'}"
  done
  [ -n "$secs" ]
}

# heading_match <text> <inline>: true iff <text> opens at least one section.
heading_match() { sections_of "$1" "$2"; }

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

# check_findings <surface> <action> <inline>: the finding scan the header
# describes, over every unfenced line of <surface>; never returns on deny. No
# here-string or heredoc: both need a writable TMPDIR on bash 3.2.
check_findings() {
  local rest="$1" line t d mk fnd disp fence=0 arrow=$'\xe2\x86\x92' want='re-dispatched and resolved'
  while :; do
    line="${rest%%$'\n'*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if is_fence "$line" "$3"; then
      fence=$((1 - fence))
    elif [ "$fence" = 0 ]; then
      t="$line"; mk=0; fnd=0; d="${t%%[!0-9]*}"
      case "$t" in
        "- "*|"* "*) mk=1; t="${t#??}" ;;
        *) [ -n "$d" ] && [ "${t:${#d}:2}" = ". " ] && { mk=1; t="${t:${#d}+2}"; } ;;
      esac
      t="${t#\*\*}"
      case "$t" in
        "[Minor]"*) ;;
        "[Critical]"*|"[Important]"*) fnd=1 ;;
        *) [ "$mk" = 1 ] && [[ "$t" == *"$arrow"* ]] && fnd=1 ;;
      esac
      disp=""
      [[ "$line" == *"$arrow"* ]] && disp="${line##*"$arrow"}"
      disp="${disp#"${disp%%[![:space:]]*}"}"
      [ "$fnd" = 1 ] && [[ ! "$disp" =~ $re_ok ]] && deny "the PR body's '$heading' section has a Critical or Important finding whose disposition is not '$want': $line. Record it as $want before $2,"
    fi
    [[ "$rest" == *$'\n'* ]] || break
    rest="${rest#*$'\n'}"
  done
}

# check_verdict <surface> <action> <inline>: reads EVERY slot in every section
# and denies on the first one not accepted; never returns on deny.
check_verdict() {
  local rest tok
  sections_of "$1" "$3"
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
      file_content="${file_content#"$bom"}"
      have_file_content=1
    else
      exit 0   # fail-open: --body-file referenced but unreadable
    fi
  fi

  # Wide-surface check: the whole command string for inline --body/-b (never
  # a narrowly extracted substring - see header note), the whole file content
  # for --body-file/-F. Either surface's section is enough; both are scanned
  # for findings.
  if [ "$has_body" = "1" ] && heading_match "$cmd" 1; then
    check_verdict "$cmd" "opening the PR" 1
  elif [ "$have_file_content" = "1" ] && heading_match "$file_content" 0; then
    check_verdict "$file_content" "opening the PR" 0
  else
    deny "the PR body is missing the required '$heading' section. Add one before opening the PR,"
  fi
  check_findings "$cmd" "opening the PR" 1
  check_findings "$file_content" "opening the PR" 0
  exit 0
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
  pr_body="${pr_body#"$bom"}"
  pr_base="$(printf '%s' "$view_json" | jq -r '.baseRefName // empty' 2>/dev/null)"
  pr_base="${pr_base%$'\r'}"

  [ -n "$protected" ] && [ "$pr_base" = "$protected" ] && exit 0

  if [ -z "$pr_body" ]; then
    deny "the PR's body (fetched via gh pr view) is empty, so the required '$heading' section can't be verified. Add the section to the PR body,"
  fi

  heading_match "$pr_body" 0 || deny "the PR body is missing the required '$heading' section. Add one before merging the PR,"
  check_verdict "$pr_body" "merging the PR" 0
  check_findings "$pr_body" "merging the PR" 0
fi

exit 0
