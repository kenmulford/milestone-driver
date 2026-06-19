#!/usr/bin/env bash
# milestone-driver — CI-aware preflight step discovery (issue #162).
#
# Discovers the runnable shell steps of a repo's PR-gating GitHub Actions
# workflows so `preflightCmd: "github-ci"` can front-run CI's cheap checks
# locally. The workflows are LOCAL files in the checkout — this reads them from
# disk and NEVER calls the network. A constrained, line-oriented parser handles
# the NARROW surface only (jobs -> steps -> run/working-directory/if/uses/
# continue-on-error + the workflow `on:` trigger). NO YAML library, NO new
# dependency (no yq/act/python) — see the design spec's "Build decision".
#
# Usage:   ci-preflight-steps.sh [REPO_ROOT] [CI_WORKFLOW]
#   REPO_ROOT    path to a checked-out repo root (default: CWD).
#   CI_WORKFLOW  optional workflow-file basename (e.g. "ci.yml") to narrow to one
#                workflow (the optional `ciWorkflow` profile value).
#
# Output (stdout): a deterministic, line-oriented, TAB-separated record stream,
# ordered by workflow filename ascending, then job + step declaration order:
#   STEP <wf> <job> <coe> <wdir> <cmd>   a runnable step. coe=1 when the step is
#                                        continue-on-error (a failure never counts
#                                        as real). wdir is the working-directory
#                                        ("" = repo root). cmd has newlines encoded
#                                        as "\n" and backslashes as "\\".
#   SKIP <wf> <job> <reason> <detail>    a step skipped (with the reason).
#   CHECK <name>                         a mirrored check name ("<wf>/<job>/<step>").
#   WARN <message>                       a VISIBLE warning (silent-under-run guard,
#                                        parse error, etc.).
#   SUMMARY mirrored=<N> skipped=<M>     coverage counts (always last).
# Fail-open: a parse error or no `.github/workflows` emits a clear reason + an
# empty step list (the gate then no-ops), never a hard crash. Exit 0 always.
set -u
export LC_ALL=C

ROOT="${1:-$PWD}"
ONLY_WF="${2:-}"
ROOT="${ROOT%/}"

mirrored=0
skipped=0
# Buffered emission so SUMMARY can come last while STEP/SKIP/CHECK stream in order.
out_lines=()
emit() { out_lines+=("$1"); }
flush() { local l; for l in "${out_lines[@]:-}"; do [ -n "$l" ] && printf '%s\n' "$l"; done; printf 'SUMMARY\tmirrored=%s\tskipped=%s\n' "$mirrored" "$skipped"; }

WFDIR="$ROOT/.github/workflows"
if [ ! -d "$WFDIR" ]; then
  emit "WARN	no .github/workflows directory found at $ROOT — nothing to mirror"
  flush; exit 0
fi

# Collect workflow files (*.yml, *.yaml), sorted by basename ascending for determinism.
shopt -s nullglob
declare -a WFILES=()
for f in "$WFDIR"/*.yml "$WFDIR"/*.yaml; do WFILES+=("$f"); done
shopt -u nullglob
if [ "${#WFILES[@]}" -eq 0 ]; then
  emit "WARN	no workflow files in $WFDIR — nothing to mirror"
  flush; exit 0
fi
# Sort by basename (deterministic order independent of glob/locale quirks).
IFS=$'\n' WFILES=($(for f in "${WFILES[@]}"; do printf '%s\t%s\n' "$(basename "$f")" "$f"; done | sort | cut -f2-)); unset IFS

INTEGRATION_BRANCH=""
PROFILE="$ROOT/.milestone-config/driver.json"
[ -f "$PROFILE" ] || PROFILE="$ROOT/milestone-driver.json"
if [ -f "$PROFILE" ] && command -v jq >/dev/null 2>&1; then
  INTEGRATION_BRANCH="$(jq -r '.integrationBranch // empty' "$PROFILE" 2>/dev/null)"; INTEGRATION_BRANCH="${INTEGRATION_BRANCH%$'\r'}"
fi

# indent_of <line> -> count of leading SPACE characters before the first
# non-space (YAML forbids tab indent). Matches the pwsh sibling's Get-Indent
# (regex ^[ ]*): a leading tab stops the count, it is NOT treated as indent.
indent_of() { local s="$1"; local rest="${s#"${s%%[! ]*}"}"; echo $(( ${#s} - ${#rest} )); }
# strip_comment <value> -> drop a trailing " # comment" (best-effort; not inside quotes).
strip_inline() { local v="$1"; printf '%s' "$v" | sed -E 's/[[:space:]]+#.*$//'; }
# trim <s>
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
# unquote <s> -> strip matching leading/trailing single or double quotes.
unquote() { local s="$1"; case "$s" in \"*\") s="${s#\"}"; s="${s%\"}";; \'*\') s="${s#\'}"; s="${s%\'}";; esac; printf '%s' "$s"; }
# encode_cmd: newline -> "\n", backslash -> "\\" (so a multi-line run: is one record).
encode_cmd() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' | awk 'BEGIN{ORS=""} {if(NR>1) printf "\\n"; printf "%s",$0}'; }

# --- PR-gating detection (narrow `on:` parse) -------------------------------
# Returns 0 if the workflow triggers on pull_request, OR on push to the
# integration branch. Best-effort over the common `on:` shapes.
is_pr_gating() {
  local file="$1" val indent on_indent=-1 in_on=0 cur_trigger="" trigger_indent=-1
  local has_pr=0 has_push=0 push_subkeys=0 push_branches_key=0 push_branch_ok=0 in_branches=0 branches_indent=-1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    # full-line comment / blank only (anchor to leading #; do NOT drop a line with
    # a trailing/inline # such as `uses: x # pin` or `run: grep '#define'`).
    local trimmed; trimmed="$(trim "$line")"
    case "$trimmed" in ''|'#'*) continue;; esac
    indent="$(indent_of "$line")"
    local content; content="$trimmed"
    if [ "$in_on" -eq 0 ]; then
      case "$content" in
        on:*|'"on":'*|"'on':"*)
          on_indent="$indent"; in_on=1
          val="$(trim "${content#*:}")"
          # inline forms: `on: push`, `on: [push, pull_request]`, `on: {pull_request: ...}`
          case "$val" in *pull_request*) has_pr=1;; esac
          # bare inline push (`on: push` / `on: [push]`) = all branches -> treat as gating.
          case "$val" in *push*) has_push=1; push_subkeys=0;; esac
          [ -n "$val" ] && in_on=0   # inline on: — done after this line
          ;;
      esac
      continue
    fi
    # inside the on: block — a line at/below on_indent ends it.
    if [ "$indent" -le "$on_indent" ]; then break; fi
    # trigger sub-keys (e.g. branches:, tags:, paths:) live deeper than the trigger key.
    if [ "$indent" -gt "$trigger_indent" ] && [ "$trigger_indent" -ge 0 ]; then
      if [ "$cur_trigger" = "push" ]; then
        push_subkeys=1
        case "$content" in branches:*|branches) push_branches_key=1; in_branches=1; branches_indent="$indent";; esac
        # inline branches list: `branches: [develop, main]`
        if [ "$push_branches_key" -eq 1 ] && [ "$in_branches" -eq 1 ]; then
          case "$content" in branches:*)
            val="$(trim "${content#branches:}")"
            case "$val" in \[*\]) val="${val#[}"; val="${val%]}";
              local IFS=','; local b
              for b in $val; do b="$(unquote "$(trim "$b")")"; [ -n "$INTEGRATION_BRANCH" ] && [ "$b" = "$INTEGRATION_BRANCH" ] && push_branch_ok=1; done;;
            esac;;
          esac
          # block branch list item: `- develop`
          case "$content" in -*) val="$(unquote "$(trim "${content#-}")")"; [ -n "$INTEGRATION_BRANCH" ] && [ "$val" = "$INTEGRATION_BRANCH" ] && push_branch_ok=1;; esac
        fi
      fi
      continue
    fi
    # a trigger key (one level under on:)
    case "$content" in
      pull_request:*|pull_request|pull_request_target:*|pull_request_target) has_pr=1; cur_trigger="pull_request"; trigger_indent="$indent"; in_branches=0;;
      push:*|push) has_push=1; cur_trigger="push"; trigger_indent="$indent"; push_subkeys=0; in_branches=0;;
      *) cur_trigger="other"; trigger_indent="$indent"; in_branches=0;;
    esac
  done < "$file"
  # pull_request anywhere -> gating.
  if [ "$has_pr" -eq 1 ]; then return 0; fi
  # push -> gating only if it targets all branches (no sub-key filters) OR explicitly the
  # integration branch. A push with only tags:/paths: filters (e.g. a tag-release workflow)
  # is NOT a PR gate.
  if [ "$has_push" -eq 1 ]; then
    [ "$push_subkeys" -eq 0 ] && return 0
    [ "$push_branches_key" -eq 1 ] && [ "$push_branch_ok" -eq 1 ] && return 0
  fi
  return 1
}

# --- Step extraction --------------------------------------------------------
# Walks jobs -> steps; for each step decides emit-as-STEP or SKIP. Narrow parse:
# tracks `steps:` blocks and `- ` step boundaries by indentation.
extract_workflow() {
  local file="$1" wfname; wfname="$(basename "$file")"
  local line content indent
  local in_jobs=0 jobs_indent=-1
  local cur_job="" job_indent=-1
  local in_steps=0 steps_indent=-1 step_marker_indent=-1
  local step_idx=0
  # per-job accumulators (reset at each job header)
  local job_uses="" job_services=0 job_emitted=0
  # per-step accumulators
  local s_run="" s_run_active=0 s_run_indent=-1 s_run_block=0
  local s_wdir="" s_if="" s_uses="" s_coe=0 s_secrets=0 s_services_ref=0
  local has_step=0

  # finalize_job: when a job had a job-level `uses:` (reusable/composite workflow call)
  # and emitted no steps of its own, record it as a skipped reusable-workflow call — the
  # silent-under-run case the warning guard exists for.
  finalize_job() {
    [ -z "$cur_job" ] && return
    if [ -n "$job_uses" ] && [ "$job_emitted" -eq 0 ]; then
      emit "SKIP	$wfname	$cur_job	uses-reusable-workflow	$job_uses"; skipped=$((skipped+1))
    fi
    job_uses=""; job_services=0; job_emitted=0
  }
  reset_job() { job_uses=""; job_services=0; job_emitted=0; }

  finalize_step() {
    [ "$has_step" -eq 0 ] && return
    job_emitted=1
    step_idx=$((step_idx+1))
    local label="$wfname/$cur_job/step$step_idx"
    # classify — order matters (most specific skip reason wins)
    if [ -n "$s_uses" ]; then
      emit "SKIP	$wfname	$cur_job	uses-step	$s_uses"; skipped=$((skipped+1)); reset_step; return
    fi
    if [ -z "$s_run" ]; then
      # no run: and no uses: — e.g. a bare `- name:` or unsupported shape; skip quietly.
      emit "SKIP	$wfname	$cur_job	no-run	step has no run: command"; skipped=$((skipped+1)); reset_step; return
    fi
    if [ "$s_secrets" -eq 1 ]; then
      emit "SKIP	$wfname	$cur_job	secrets	references secrets"; skipped=$((skipped+1)); reset_step; return
    fi
    if [ "$s_services_ref" -eq 1 ] || [ "$job_services" -eq 1 ]; then
      emit "SKIP	$wfname	$cur_job	services-or-deploy	job/step uses a service container or deploy/publish"; skipped=$((skipped+1)); reset_step; return
    fi
    case "$s_run" in
      *'${{'*) emit "SKIP	$wfname	$cur_job	interpolation	run: contains \${{ }} expression"; skipped=$((skipped+1)); reset_step; return;;
    esac
    if [ -n "$s_if" ]; then
      emit "SKIP	$wfname	$cur_job	step-if	step-level if: ($s_if)"; skipped=$((skipped+1)); reset_step; return
    fi
    # runnable
    local enc; enc="$(encode_cmd "$s_run")"
    emit "STEP	$wfname	$cur_job	$s_coe	$s_wdir	$enc"
    emit "CHECK	$label"
    mirrored=$((mirrored+1))
    reset_step
  }
  reset_step() {
    s_run=""; s_run_active=0; s_run_indent=-1; s_run_block=0; block_base=-1
    s_wdir=""; s_if=""; s_uses=""; s_coe=0; s_secrets=0; s_services_ref=0
    has_step=0
  }
  local block_base=-1

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    # blank / comment lines: inside a block run: they may be content; otherwise skip.
    if [ "$s_run_active" -eq 1 ] && [ "$s_run_block" -eq 1 ]; then
      # block scalar collects lines more-indented than the run: key
      indent="$(indent_of "$line")"
      if [ -z "$(trim "$line")" ]; then
        [ -n "$s_run" ] && s_run="$s_run"$'\n'""
        continue
      fi
      if [ "$indent" -gt "$s_run_indent" ]; then
        # The block's base indent is set by its first content line; strip exactly that
        # many leading spaces from every line (YAML block-scalar de-indent).
        [ "$block_base" -lt 0 ] && block_base="$indent"
        local body="${line:$block_base}"
        if [ -n "$s_run" ]; then s_run="$s_run"$'\n'"$body"; else s_run="$body"; fi
        continue
      else
        s_run_active=0; s_run_block=0; block_base=-1   # block ended; fall through to re-process this line
      fi
    fi
    # full-line comment / blank only (anchor to leading #; do NOT drop a line with
    # a trailing/inline # such as `uses: x # pin` or `pull_request: # PRs only`).
    content="$(trim "$line")"
    case "$content" in ''|'#'*) continue;; esac
    indent="$(indent_of "$line")"

    # detect jobs:
    if [ "$in_jobs" -eq 0 ]; then
      case "$content" in
        jobs:) in_jobs=1; jobs_indent="$indent";;
      esac
      continue
    fi
    # a top-level key at or below jobs_indent ends the jobs block
    if [ "$indent" -le "$jobs_indent" ] && [ "$in_jobs" -eq 1 ]; then
      finalize_step; finalize_job; cur_job=""
      case "$content" in
        jobs:) in_jobs=1; jobs_indent="$indent"; in_steps=0;;
        *) in_jobs=0;;
      esac
      continue
    fi

    # job header: a key one level under jobs (indent > jobs_indent, ends with ':')
    if [ "$in_steps" -eq 0 ] && [ "$indent" -gt "$jobs_indent" ]; then
      if [ "$cur_job" = "" ] || [ "$indent" -le "$job_indent" ]; then
        case "$content" in
          *:) finalize_step; finalize_job; cur_job="${content%%:*}"; cur_job="$(trim "$cur_job")"; job_indent="$indent"; in_steps=0; step_idx=0; reset_job; continue;;
        esac
      fi
      # job-level keys (deeper than the job header, before steps:): uses: / services:
      case "$content" in
        uses:*) job_uses="$(unquote "$(trim "$(strip_inline "${content#uses:}")")")"; continue;;
        services:*|services) job_services=1; continue;;
      esac
    fi

    # entering steps:
    case "$content" in
      steps:)
        finalize_step
        in_steps=1; steps_indent="$indent"; step_marker_indent=-1; continue;;
    esac

    if [ "$in_steps" -eq 1 ]; then
      # a key at/below steps_indent ends the steps block (next job key, or new top-level)
      if [ "$indent" -le "$job_indent" ] && [ "$indent" -le "$steps_indent" ]; then
        finalize_step
        in_steps=0
        # re-evaluate as job header or jobs-end
        if [ "$indent" -le "$jobs_indent" ]; then finalize_job; cur_job=""; in_jobs=0; continue; fi
        case "$content" in
          *:) finalize_job; cur_job="${content%%:*}"; cur_job="$(trim "$cur_job")"; job_indent="$indent"; step_idx=0; reset_job; continue;;
        esac
        continue
      fi
      # new step list item: "- key: val" or "-"
      case "$content" in
        -*)
          finalize_step
          has_step=1; step_marker_indent="$indent"
          # the part after "- " may itself be a key: val
          local after; after="$(trim "${content#-}")"
          content="$after"
          [ -z "$content" ] && continue
          ;;
      esac
      # step attribute lines (and the after-dash key handled above)
      local k v
      case "$content" in
        run:*)
          v="$(trim "${content#run:}")"
          case "$v" in
            '|'*|'>'*)
              s_run_active=1; s_run_block=1; s_run_indent="$indent"; s_run=""
              ;;
            '')
              s_run_active=1; s_run_block=1; s_run_indent="$indent"; s_run=""
              ;;
            *)
              s_run="$(unquote "$(strip_inline "$v")")"
              ;;
          esac
          ;;
        working-directory:*) s_wdir="$(unquote "$(trim "$(strip_inline "${content#working-directory:}")")")";;
        if:*) s_if="$(trim "${content#if:}")";;
        uses:*) s_uses="$(unquote "$(trim "$(strip_inline "${content#uses:}")")")";;
        continue-on-error:*) v="$(trim "$(strip_inline "${content#continue-on-error:}")")"; [ "$v" = "true" ] && s_coe=1;;
        with:*|env:*|name:*|id:*|services:*) : ;;
      esac
      # secrets / services / deploy reference anywhere in the step's key lines
      case "$content" in *secrets.*|*'secrets['*) s_secrets=1;; esac
      case "$content" in *services:*) s_services_ref=1;; esac
    fi
  done < "$file"
  finalize_step
  finalize_job
  : "$step_marker_indent"  # referenced to silence set-but-unused; reserved for future step-boundary use
}

any_gating=0
for wf in "${WFILES[@]}"; do
  base="$(basename "$wf")"
  if [ -n "$ONLY_WF" ] && [ "$base" != "$ONLY_WF" ]; then continue; fi
  if ! is_pr_gating "$wf"; then
    emit "SKIP	$base	-	not-pr-gating	workflow not triggered on pull_request or push to integration branch"
    continue
  fi
  any_gating=1
  before_mirrored="$mirrored"
  extract_workflow "$wf"
  # silent-under-run guard, per gating workflow: gating but produced no runnable steps
  if [ "$mirrored" -eq "$before_mirrored" ]; then
    emit "WARN	PR-gating workflow '$base' produced ZERO runnable steps (real checks may live behind a uses: reusable/composite workflow) — this is NOT a clean pass"
  fi
done

if [ -n "$ONLY_WF" ] && [ "$any_gating" -eq 0 ]; then
  emit "WARN	ciWorkflow '$ONLY_WF' matched no PR-gating workflow in $WFDIR"
fi
if [ "$any_gating" -eq 0 ] && [ -z "$ONLY_WF" ]; then
  emit "WARN	no PR-gating workflow found in $WFDIR (none triggered on pull_request or push to integration branch) — nothing to mirror"
fi

flush
exit 0
