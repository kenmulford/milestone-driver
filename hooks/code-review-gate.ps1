#!/usr/bin/env pwsh
# milestone-driver — code-review-gate (Claude PreToolUse: Bash,
# if: Bash(gh pr create *) / Bash(gh pr merge *)).
#
# Bash parity of code-review-gate.sh — see that file for the full design note.
# create: detects a --body/-b or --body-file/-F SIGNAL (presence only — NOT a
# precisely delimited value) and checks the heading against the WIDEST
# available surface: the whole decoded command string for inline --body/-b,
# the whole referenced file's content for --body-file/-F. A deliberate
# re-bias toward fail-open (issue #289 review round 2) — precisely EXTRACTING
# the --body value via quote-matched capture truncated early on an escaped
# quote or this repo's own `--body "$(cat <<'EOF' ... EOF)"` heredoc pattern
# with any quote before the heading, producing a false BLOCK on the repo's own
# documented PR shape. merge: gh's own -b/--body/-F on `gh pr merge` set the
# MERGE COMMIT message, not the PR body, and every real invocation in this
# repo passes neither — so the merge path always fetches the PR's current
# body via `gh pr view`.
#
# Heading match is ANCHORED, not a bare substring: `## Code Review` must be
# followed by a non-alphanumeric character or end-of-string, so "## Code
# Reviewer says LGTM" does NOT satisfy the gate.
#
# Exemption: a command targeting protectedBranch (create's --base/-B, or a
# merge whose fetched baseRefName is protectedBranch) is exempt.
#
# Deny: exit 2 + stderr. Escape: CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1.
# Fail-open: unparsed stdin, gh unavailable, an unreadable --body-file, or a
# failed `gh pr view` all exit 0.

if ($env:CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE -eq '1') { exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$cmd = $hook.tool_input.command
if (-not $cmd) { exit 0 }

$isCreate = [bool]($cmd -match 'gh\s+pr\s+create')
$isMerge  = [bool]($cmd -match 'gh\s+pr\s+merge')
if (-not $isCreate -and -not $isMerge) { exit 0 }

$projectDir = $hook.cwd
if (-not $projectDir) { $projectDir = $env:CLAUDE_PROJECT_DIR }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = ([string]$projectDir) -replace '\\', '/'
$profilePath = Join-Path $projectDir '.milestone-config/driver.json'
if (-not (Test-Path $profilePath)) { $profilePath = Join-Path $projectDir 'milestone-driver.json' }
$protected = $null
if (Test-Path $profilePath) {
  try {
    $cfg = Get-Content $profilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $protected = $cfg.protectedBranch
  } catch { $protected = $null }
}

$heading = '## Code Review'
$suffix = " or set CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1 to override."

function Deny([string]$msg) {
  [Console]::Error.WriteLine("milestone-driver: $msg$suffix")
  exit 2
}

# HeadingMatch <text> — true iff <text> contains an ANCHORED `## Code Review`
# (not immediately followed by a letter/digit; end-of-string also satisfies
# the anchor). [regex]::Escape guards against $heading ever containing a
# regex metacharacter.
function HeadingMatch([string]$text) {
  if (-not $text) { return $false }
  return [regex]::IsMatch($text, [regex]::Escape($heading) + '($|[^A-Za-z0-9])')
}

if ($isCreate) {
  # Exemption: --base/-B <protectedBranch> (mirrors no-pr-to-protected.ps1:37).
  if ($protected -and ($cmd -match '(?:--base[=\s]+|-B\s+)["'']?([^\s"'']+)')) {
    if ($matches[1] -eq $protected) { exit 0 }
  }

  # Presence-only signal detection (NOT value extraction — see header note).
  $hasBody = [bool]($cmd -match '(^|\s)(--body|-b)([=\s]|$)')
  $hasFile = [bool]($cmd -match '(^|\s)(--body-file|-F)([=\s]|$)')

  if (-not $hasBody -and -not $hasFile) {
    Deny "gh pr create has no --body/--body-file argument, so the required '$heading' section can't be verified. Add a PR body containing that section,"
  }

  # --body-file/-F: the PATH itself is a simple single token (mirrors the
  # --base extraction above), so quote-matching it carries none of the
  # multi-word/multi-line truncation risk the inline --body value did.
  $fileContent = $null
  if ($hasFile) {
    $fm = [regex]::Match($cmd, '(?:--body-file|-F)[=\s]+"(?<v>[^"]*)"')
    if (-not $fm.Success) { $fm = [regex]::Match($cmd, '(?:--body-file|-F)[=\s]+''(?<v>[^'']*)''') }
    if (-not $fm.Success) { $fm = [regex]::Match($cmd, '(?:--body-file|-F)[=\s]+(?<v>\S+)') }
    if (-not $fm.Success) { exit 0 }   # fail-open: flag present but no parseable path
    $bf = $fm.Groups['v'].Value
    if ($bf -notmatch '^/') { $bf = Join-Path $projectDir $bf }
    if (Test-Path $bf -PathType Leaf) {
      try { $fileContent = Get-Content $bf -Raw -ErrorAction Stop }
      catch { exit 0 }
    } else {
      exit 0   # fail-open: --body-file referenced but unreadable
    }
  }

  # Wide-surface check: the whole command string for inline --body/-b (never
  # a narrowly extracted substring — see header note), the whole file content
  # for --body-file/-F. Either surface matching is enough to allow.
  if ($hasBody -and (HeadingMatch $cmd)) { exit 0 }
  if ($fileContent -and (HeadingMatch $fileContent)) { exit 0 }

  Deny "the PR body is missing the required '$heading' section. Add one before opening the PR,"
}

if ($isMerge) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { exit 0 }

  $prArg = $null
  $pm = [regex]::Match($cmd, 'pr\s+merge\s+([^\s-][^\s]*)')
  if ($pm.Success) { $prArg = $pm.Groups[1].Value }

  $viewJson = $null
  try {
    if ($prArg) {
      $viewJson = (& gh pr view $prArg --json body,baseRefName 2>$null) -join "`n"
    } else {
      $viewJson = (& gh pr view --json body,baseRefName 2>$null) -join "`n"
    }
    if ($LASTEXITCODE -ne 0) { exit 0 }
  } catch { exit 0 }
  if ([string]::IsNullOrWhiteSpace($viewJson)) { exit 0 }

  try { $view = $viewJson | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
  $prBody = $view.body
  $prBase = $view.baseRefName

  if ($protected -and $prBase -eq $protected) { exit 0 }

  if ([string]::IsNullOrEmpty($prBody)) {
    Deny "the PR's body (fetched via gh pr view) is empty, so the required '$heading' section can't be verified. Add the section to the PR body,"
  }

  if (HeadingMatch $prBody) { exit 0 }
  Deny "the PR body is missing the required '$heading' section. Add one before merging the PR,"
}

exit 0
