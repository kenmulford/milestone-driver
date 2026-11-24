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
# Heading match is ANCHORED, not a bare substring: `## Code Review` must open
# a section and be followed by a non-alphanumeric character or end-of-string,
# so "## Code Reviewer says LGTM" does NOT satisfy the gate.
#
# Verdict parse (issue #604): the gate also reads the `/code-review run:`
# value. Accepted: `yes` and `n/a - <reason>`; `deferred` was retired by the
# v1.24.0 simplify pass, for the reason the .sh sibling's header records. `no`,
# an unrecognized value, an empty value, and a missing slot all DENY. EVERY
# slot in EVERY section is read (milestone #54), so a `no` under any
# section or `### #<n>` block denies. See code-review-gate.sh for the section
# rule and why the token is unwrapped of one quote per side.
#
# Finding scan (issue #804): after the verdict slots pass, every unfenced line
# of the checked text is scanned, sections ignored, so no body shape can hide a
# finding. See code-review-gate.sh for the full rule.
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

# Sections <text> <inline>: every section's unfenced lines from the heading
# on, each ending in a newline, '' when <text> holds none; the rule is
# code-review-gate.sh's is_fence, open_at and sections_of.
# [ \t\n\v\f\r] stands for the .sh twin's [[:space:]], which \s would widen.
$reHeadAt = [regex]::Escape($heading) + '(?![A-Za-z0-9])'
$rePre = '^[ \t\n\v\f\r]*$|(^|[ \t\n\v\f\r])(--body[ =]|-b |[A-Za-z_][A-Za-z0-9_]*=)("|''|\$'')$'
$reOk = '^re-dispatched and resolved(\.| \([^()]*\))?[ \t\n\v\f\r]*["'']?$'
$sp = [char[]]" `t`n`v`f`r"
function IsFence([string]$lead, [bool]$inline) {
  return $lead.StartsWith('```', $ord) -or ($inline -and $lead.StartsWith('\`\`\`', $ord))
}
function Sections([string]$text, [bool]$inline) {
  $sb = [System.Text.StringBuilder]::new()
  $on = $false; $fence = $false
  foreach ($line in $text.Split("`n")) {
    $lead = $line.TrimStart($sp)
    if (IsFence $lead $inline) { $fence = -not $fence; continue }
    if ($fence) { continue }
    $at = -1
    foreach ($m in [regex]::Matches($line, $reHeadAt)) {
      if ([regex]::IsMatch($line.Substring(0, $m.Index), $rePre)) { $at = $m.Index; break }
    }
    if ($at -ge 0) { $line = $line.Substring($at); $on = $true }
    elseif ($lead.StartsWith('## ', $ord)) { $on = $false }
    if ($on) { [void]$sb.Append($line).Append("`n") }
  }
  return $sb.ToString()
}

function HeadingMatch([string]$text, [bool]$inline) { return [bool](Sections $text $inline) }

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

# CheckFindings <text> <action> <inline>: the finding scan code-review-gate.sh's
# header describes, over every unfenced line of <text>; never returns on deny.
# Ordinal throughout, so it trims, cuts and matches exactly as that file does.
function CheckFindings([string]$text, [string]$action, [bool]$inline) {
  $arrow = [string][char]0x2192
  $want = 're-dispatched and resolved'
  $fence = $false
  foreach ($raw in $text.Split("`n")) {
    $line = $raw.Trim($sp)
    if (IsFence $line $inline) { $fence = -not $fence; continue }
    if ($fence) { continue }
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
    if ($k -ge 0) { $disp = $line.Substring($k + 1).TrimStart($sp) }
    if (-not [regex]::IsMatch($disp, $reOk)) {
      Deny "the PR body's '$heading' section has a Critical or Important finding whose disposition is not '$want': ${line}. Record it as $want before $action,"
    }
  }
}

# CheckVerdict <surface> <action> <inline>: reads EVERY slot in every section
# and denies on the first one not accepted; never returns on deny.
function CheckVerdict([string]$surface, [string]$action, [bool]$inline) {
  $span = Sections $surface $inline
  if ($span.IndexOf($runSlot, $ord) -lt 0) {
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
  # for --body-file/-F. Either surface's section is enough; both are scanned
  # for findings.
  if ($hasBody -and (HeadingMatch $cmd $true)) { CheckVerdict $cmd 'opening the PR' $true }
  elseif ($fileContent -and (HeadingMatch $fileContent $false)) { CheckVerdict $fileContent 'opening the PR' $false }
  else { Deny "the PR body is missing the required '$heading' section. Add one before opening the PR," }
  CheckFindings $cmd 'opening the PR' $true
  CheckFindings $fileContent 'opening the PR' $false
  exit 0
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
  $prBody = [string]$view.body
  if ($prBody.StartsWith([string][char]0xFEFF, $ord)) { $prBody = $prBody.Substring(1) }
  $prBase = $view.baseRefName

  if ($protected -and $prBase -eq $protected) { exit 0 }

  if ([string]::IsNullOrEmpty($prBody)) {
    Deny "the PR's body (fetched via gh pr view) is empty, so the required '$heading' section can't be verified. Add the section to the PR body,"
  }

  if (-not (HeadingMatch $prBody $false)) { Deny "the PR body is missing the required '$heading' section. Add one before merging the PR," }
  CheckVerdict $prBody 'merging the PR' $false
  CheckFindings $prBody 'merging the PR' $false
}

exit 0
