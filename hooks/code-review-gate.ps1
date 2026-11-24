#!/usr/bin/env pwsh
# milestone-driver - code-review-gate (Claude PreToolUse: Bash,
# if: Bash(gh pr create *) / Bash(gh pr merge *)).
#
# Bash parity of code-review-gate.sh - see that file for the full design note.
# create: detects a --body/-b or --body-file/-F SIGNAL (presence only - NOT a
# precisely delimited value) and checks the heading against the WIDEST
# available surface: the whole decoded command string for inline --body/-b,
# the whole referenced file's content for --body-file/-F. A deliberate
# re-bias toward fail-open (issue #289 review round 2) - precisely EXTRACTING
# the --body value via quote-matched capture truncated early on an escaped
# quote or this repo's own `--body "$(cat <<'EOF' ... EOF)"` heredoc pattern
# with any quote before the heading, producing a false BLOCK on the repo's own
# documented PR shape. merge: the driver's own squash merges pass --subject and
# --body; the release and back-merge rituals merge with a bare --merge and pass
# neither. Both flags set the MERGE COMMIT message, never the PR body - so the
# merge path fetches the PR's current body via `gh pr view`.
#
# Heading match is ANCHORED, not a bare substring: `## Code Review` must be
# followed by a non-alphanumeric character or end-of-string, so "## Code
# Reviewer says LGTM" does NOT satisfy the gate.
#
# Verdict parse (issue #604): the gate also reads the `/code-review run:`
# value. Accepted: `yes` and `n/a - <reason>`; `deferred` was retired by the
# v1.24.0 simplify pass, for the reason the .sh sibling's header records. `no`,
# an unrecognized value, an empty value, and a missing slot all DENY. The verdict
# search is SCOPED to a heading span so an incidental `/code-review run:` in
# prose ABOVE the section never false-denies: the anchored heading matches are
# walked LAST TO FIRST and the first whose text CONTAINS the slot wins. EVERY
# slot in that span is read, so a `no` under a wave PR's second `### #<n>`
# block denies even when the first reads `yes`. The heading search itself
# stays unscoped. See code-review-gate.sh for the full note, including why
# begins-a-line was rejected and why the token is unwrapped of one quote per
# side.
#
# Finding scan (issue #804): after the verdict slots pass, the finding lines are
# scanned. See code-review-gate.sh for the full rule.
#
# Exemption: a command targeting protectedBranch (create's --base/-B, or a
# merge whose fetched baseRefName is protectedBranch) is exempt.
#
# Deny: hook-deny.{sh,ps1} (Claude: exit 2 + stderr, Codex: stdout JSON). Escape: CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1.
# Fail-open: unparsed stdin, gh unavailable, an unreadable --body-file, or a
# failed `gh pr view` all exit 0.

if ($env:CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE -eq '1') { exit 0 }

# UTF-8 without a BOM both ways: the payload and the deny quote a finding line
# carrying the arrow, and the Windows console default (OEM) would corrupt it.
# Set only when not already UTF-8: each setter replaces the console reader or
# writer, which drops the redirected stdin and stderr of tests/_lib.ps1's
# in-process runner.
try {
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  if ([Console]::InputEncoding.CodePage -ne 65001) { [Console]::InputEncoding = $utf8 }
  if ([Console]::OutputEncoding.CodePage -ne 65001) { [Console]::OutputEncoding = $utf8 }
} catch { }
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
. (Join-Path $PSScriptRoot 'hook-deny.ps1')

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
$runSlot = '/code-review run:'
$suffix = " or set CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=1 to override."
# Ordinal on every string search: the culture-sensitive overload treats CRLF as
# one text element under ICU, so a CRLF body could hide its newline.
$ord = [System.StringComparison]::Ordinal

function Deny([string]$msg) {
  Invoke-HookDeny $hook ("milestone-driver: $msg$suffix")
}

# HeadingMatch <text> - true iff <text> contains an ANCHORED `## Code Review`
# (not immediately followed by a letter/digit; end-of-string also satisfies
# the anchor). [regex]::Escape guards against $heading ever containing a
# regex metacharacter.
function HeadingMatch([string]$text) {
  if (-not $text) { return $false }
  return [regex]::IsMatch($text, [regex]::Escape($heading) + '($|[^A-Za-z0-9])')
}

# VerdictSpan <text>: the text after the LAST anchored heading match whose text
# holds a `/code-review run:` slot, $null when none does; sets $script:lead to
# that match's line up to and including the heading, as the .sh twin does.
function VerdictSpan([string]$text) {
  $script:lead = ''
  if (-not $text) { return $null }
  $hit = $null
  $i = 0
  while (($i = $text.IndexOf($heading, $i, $ord)) -ge 0) {
    $at = $i
    $i += $heading.Length
    $after = $text.Substring($i)
    if ([regex]::IsMatch($after, '^[A-Za-z0-9]') -or $after.IndexOf($runSlot, $ord) -lt 0) { continue }
    $hit = $after
    $ls = $text.LastIndexOf([char]10, $at) + 1
    $script:lead = $text.Substring($ls, $i - $ls)
  }
  return $hit
}

# VerdictToken <after>: first whitespace-delimited token on <after>'s FIRST
# line, unwrapped of one surrounding quote character per side.
function VerdictToken([string]$after) {
  $line = $after
  $nl = $line.IndexOf("`n", $ord)
  if ($nl -ge 0) { $line = $line.Substring(0, $nl) }
  $line = $line.TrimEnd("`r")
  $m = [regex]::Match($line, '^[ \t\v\f\r]*([^ \t\v\f\r]+)')
  if (-not $m.Success) { return '' }
  $v = $m.Groups[1].Value
  if ($v[0] -eq '"' -or $v[0] -eq "'") { $v = $v.Substring(1) }
  if ($v.Length -gt 0 -and ($v[-1] -eq '"' -or $v[-1] -eq "'")) { $v = $v.Substring(0, $v.Length - 1) }
  return $v
}

# CheckFindings <surface> <action>: the finding scan code-review-gate.sh's header
# describes, over the lead and span VerdictSpan picks in <surface>; never
# returns on deny. Ordinal throughout, so it trims, cuts and matches exactly as
# that file does.
function CheckFindings([string]$surface, [string]$action) {
  $span = VerdictSpan $surface
  if ($null -eq $span) { return }
  $arrow = [string][char]0x2192
  $want = 're-dispatched and resolved'
  $ws = [char[]]" `t`r`v`f"
  $top = $true
  foreach ($raw in ($script:lead + $span).Split("`n")) {
    if (-not $top -and $raw.StartsWith('## ', $ord)) { break }
    $top = $false
    $line = $raw.Trim($ws)
    $t = $line; $mk = $false
    $num = [regex]::Match($t, '^[0-9]+\. ')
    if ($t.StartsWith('- ', $ord) -or $t.StartsWith('* ', $ord)) { $mk = $true; $t = $t.Substring(2) }
    elseif ($num.Success) { $mk = $true; $t = $t.Substring($num.Length) }
    if ($t.StartsWith('**', $ord)) { $t = $t.Substring(2) }
    if ($t.StartsWith('[Minor]', $ord)) { continue }
    $fnd = $t.StartsWith('[Critical]', $ord) -or $t.StartsWith('[Important]', $ord) -or ($mk -and $t.Contains($arrow))
    if (-not $fnd) { continue }
    $disp = ''
    $k = $line.LastIndexOf($arrow, $ord)
    if ($k -ge 0) { $disp = $line.Substring($k + 1) }
    $q = $disp.IndexOfAny([char[]]@('"', "'"))
    if ($q -ge 0) { $disp = $disp.Substring(0, $q) }
    if ($disp.Trim($ws) -cne $want) {
      Deny "the PR body's '$heading' section has a Critical or Important finding whose disposition is not '$want': ${line}. Record it as $want before $action,"
    }
  }
}

# CheckVerdict <surface> <action>: reads EVERY slot in the span and denies on
# the first one not accepted, then scans the findings; never returns on deny.
function CheckVerdict([string]$surface, [string]$action) {
  $span = VerdictSpan $surface
  if ($null -eq $span) {
    Deny "the PR body's '$heading' section has no '$runSlot' line, so no review verdict was recorded. Add one reading yes or n/a - <reason> before $action,"
  }
  $pos = 0
  while (($pos = $span.IndexOf($runSlot, $pos, $ord)) -ge 0) {
    $pos += $runSlot.Length
    $tok = VerdictToken ($span.Substring($pos))
    if (-not $tok) {
      Deny "the PR body's '$runSlot' line has an empty value, so no review verdict was recorded. Set it to yes or n/a - <reason> before $action,"
    }
    if ($tok -cne 'yes' -and $tok -cne 'n/a') {
      Deny "the PR body records '$runSlot $tok', which is not an accepted verdict. Set it to yes or n/a - <reason> before $action,"
    }
  }
  CheckFindings $surface $action
}

if ($isCreate) {
  # Exemption: --base/-B <protectedBranch>, mirroring hooks/no-pr-to-protected.ps1 (--base[=\s]+|-B\s+).
  if ($protected -and ($cmd -match '(?:--base[=\s]+|-B\s+)["'']?([^\s"'']+)')) {
    if ($matches[1] -eq $protected) { exit 0 }
  }

  # Presence-only signal detection (NOT value extraction - see header note).
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
    $driveRooted = $bf -match '^\\(?!\\)'
    $bf = $bf.Replace('\', '/')
    if ($driveRooted -and $projectDir -match '^[A-Za-z]:/') { $bf = $projectDir.Substring(0, 2) + $bf }
    if ($bf -notmatch '^(/|[A-Za-z]:/)') { $bf = Join-Path $projectDir $bf }
    if (Test-Path $bf -PathType Leaf) {
      try { $fileContent = Get-Content $bf -Raw -ErrorAction Stop }
      catch { exit 0 }
    } else {
      exit 0   # fail-open: --body-file referenced but unreadable
    }
  }

  # Wide-surface check: the whole command string for inline --body/-b (never
  # a narrowly extracted substring - see header note), the whole file content
  # for --body-file/-F. Either surface matching is enough to allow.
  if ($hasBody -and (HeadingMatch $cmd)) { CheckVerdict $cmd 'opening the PR'; exit 0 }
  if ($fileContent -and (HeadingMatch $fileContent)) { CheckVerdict $fileContent 'opening the PR'; exit 0 }

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

  if (HeadingMatch $prBody) { CheckVerdict $prBody 'merging the PR'; exit 0 }
  Deny "the PR body is missing the required '$heading' section. Add one before merging the PR,"
}

exit 0
