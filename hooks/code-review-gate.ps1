#!/usr/bin/env pwsh
# milestone-driver - code-review-gate (Claude PreToolUse: Bash, if: Bash(gh *);
# the script self-scopes to `gh pr create` / `gh pr merge`, with any global
# options (`-R <repo>`, `--repo <repo>`, any `-` token) allowed between `gh` and
# `pr`).
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
# finding. See code-review-gate.sh for the full rule, the fence and indent rules
# and the merge token walk, which also reads `-R`/`--repo` (before or after
# `merge`, else a leading `GH_REPO=<repo>` prefix before `gh` or `command gh`,
# else the last `export GH_REPO=<repo>` or bare `GH_REPO=<repo>` statement
# before it) and passes it to `gh pr view -R`; a bare statement with no export
# before it also checks the cwd repo's PR.
#
# -cmatch throughout: -match is case-insensitive, so -f (--fill) would read as
# -F, -b as -B, and `gh PR create` as gated when the .sh leg allows it. Only the
# binary matches in any case, as [Gg][Hh] on both legs.
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

$vre = '("[^"]*"|''[^'']*''|\S+)'
$ghPre = '[Gg][Hh](?:(?:\s+(?:-R|--repo)\s+' + $vre + ')|(?:\s+-\S*))*'
$isCreate = [bool]($cmd -cmatch ($ghPre + '\s+pr\s+create'))
$isMerge  = [bool]($cmd -cmatch ($ghPre + '\s+pr\s+merge'))
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
# code-review-gate.sh's block_indent, in_fence, open_at and sections_of.
# [ \t\n\v\f\r] stands for the .sh twin's [[:space:]], which \s would widen.
$reHeadAt = [regex]::Escape($heading) + '(?![A-Za-z0-9])'
$reOpen = '(^|[ \t\n\v\f\r])(--body[ \t\n\v\f\r]+|--body=|-b[ \t\n\v\f\r]+|[A-Za-z_][A-Za-z0-9_]*=)("|''|\$'')'
$rePre = $reOpen + '$'
$reBody = $reOpen + '(.*)$'
$reOk = '^re-dispatched and resolved(\.| \([^()]*\))?[ \t\n\v\f\r]*["'']?$'
$sp = [char[]]" `t`n`v`f`r"
$arrow = [string][char]0x2192

# BlockIndent <line> <inline>: <line> minus its indent, or $null when that
# indent is 4+ spaces or holds a tab (indented code, never a fence or heading).
# <inline> strips a leading tab run first, as a `<<-` heredoc does.
function BlockIndent([string]$line, [bool]$inline) {
  $s = $line
  if ($inline) { $s = $s.TrimStart("`t") }
  $b = $s.TrimStart(' ')
  if (($s.Length - $b.Length) -ge 4 -or $b.StartsWith("`t", $ord)) { return $null }
  return $b
}

# InFence <state> <line> <inline>: $true when <line> opens, closes or sits inside
# a CommonMark fenced code block; <state> is @{ ch = ''; len = 0 }, fresh per scan.
# A closer is tested on the fully trimmed line, as code-review-gate.sh's in_fence.
function InFence($st, [string]$line, [bool]$inline) {
  if ($st.ch -ne '') {
    $b = $line.TrimStart($sp)
    $run = $b.Length - $b.TrimStart([char]$st.ch).Length
    if ($run -ge $st.len -and $b.Substring($run).Trim($sp).Length -eq 0) { $st.ch = '' }
    return $true
  }
  $b = BlockIndent $line $inline
  if ($null -eq $b) { return $false }
  if ($b.StartsWith('```', $ord)) { $c = '`' }
  elseif ($b.StartsWith('~~~', $ord)) { $c = '~' }
  else { return $false }
  $run = $b.Length - $b.TrimStart([char]$c).Length
  if ($c -eq '`' -and $b.IndexOf('`', $run, $ord) -ge 0) { return $false }
  $st.ch = $c; $st.len = $run
  return $true
}

function Sections([string]$text, [bool]$inline) {
  $sb = [System.Text.StringBuilder]::new()
  $on = $false; $st = @{ ch = ''; len = 0 }
  foreach ($line in $text.Split("`n")) {
    if (InFence $st $line $inline) { continue }
    $at = -1
    foreach ($m in [regex]::Matches($line, $reHeadAt)) {
      $p = $line.Substring(0, $m.Index)
      $bp = BlockIndent $p $inline
      if (($null -ne $bp -and $bp.Length -eq 0) -or [regex]::IsMatch($p, $rePre)) { $at = $m.Index; break }
    }
    if ($at -ge 0) { $line = $line.Substring($at); $on = $true }
    else {
      $b = BlockIndent $line $inline
      if ($null -ne $b -and $b.StartsWith('## ', $ord)) { $on = $false }
    }
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
  $want = 're-dispatched and resolved'
  $st = @{ ch = ''; len = 0 }
  foreach ($raw in $text.Split("`n")) {
    if (InFence $st $raw $inline) { continue }
    $line = $raw.Trim($sp)
    $q = $null; $c = $line
    while ($true) {
      if (FindingAt $c) { $q = $c }
      if (-not $inline) { break }
      $bm = [regex]::Match($c, $reBody)
      if (-not $bm.Success) { break }
      $c = $bm.Groups[4].Value
    }
    if ($null -eq $q) { continue }
    $disp = ''
    $k = $line.LastIndexOf($arrow, $ord)
    if ($k -ge 0) { $disp = $line.Substring($k + 1).TrimStart($sp) }
    if (-not [regex]::IsMatch($disp, $reOk)) {
      Deny "the PR body's '$heading' section has a Critical or Important finding whose disposition is not '$want': ${q}. Record it as $want before $action,"
    }
  }
}

# FindingAt <text>: code-review-gate.sh's finding_at.
function FindingAt([string]$t) {
  if ($t.IndexOf('[Critical]', $ord) -ge 0 -or $t.IndexOf('[Important]', $ord) -ge 0) { return $true }
  while ($t.StartsWith('>', $ord)) { $t = $t.Substring(1).TrimStart(' ') }
  $mm = [regex]::Match($t, '^([-+*]|[0-9]+[.)])[ \t]')
  if (-not $mm.Success) { return $false }
  $t = $t.Substring($mm.Length).TrimStart([char[]]'*_')
  return (-not $t.StartsWith('[Minor]', $ord)) -and $t.Contains($arrow)
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
  # Exemption: --base/-B <protectedBranch>, mirroring hooks/no-pr-to-protected.ps1 (--base[=\s]+).
  if ($protected -and ($cmd -cmatch '(?:--base[=\s]+|-B\s+)["'']?([^\s"'']+)')) {
    if ($matches[1] -ceq $protected) { exit 0 }
  }

  # Presence-only signal detection (NOT value extraction - see header note).
  $hasBody = [bool]($cmd -cmatch '(^|\s)(--body|-b)([=\s]|$)')
  $hasFile = [bool]($cmd -cmatch '(^|\s)(--body-file|-F)([=\s]|$)')

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
    $driveRooted = $bf -cmatch '^\\(?!\\)'
    $bf = $bf.Replace('\', '/')
    if ($driveRooted -and $projectDir -cmatch '^[A-Za-z]:/') { $bf = $projectDir.Substring(0, 2) + $bf }
    if ($bf -cnotmatch '^(/|[A-Za-z]:/)') { $bf = Join-Path $projectDir $bf }
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

  # First positional token after `merge`; a stop (newline, shell operator, a
  # redirection, an unclosed quote) leaves $prArg empty and `gh pr view` reads
  # the current branch.
  $prArg = $null; $repo = $null; $flag = ''
  $pm = [regex]::Match($cmd, $ghPre + '\s+pr\s+merge')
  if ($pm.Success) {
    $rest = $cmd.Substring($pm.Index + $pm.Length); $skip = $false; $prev = ''
    $rm = [regex]::Match($pm.Value, '(?:^|\s)(?:--repo[\s=]+|-R[\s=]*)' + $vre)
    if ($rm.Success) { $repo = $rm.Groups[1].Value }
    while ($true) {
      $body = $rest.TrimStart($sp)
      $ws = $rest.Substring(0, $rest.Length - $body.Length)
      $rest = $body
      if ($rest -eq '') { break }
      if ($ws.Contains("`n") -and $prev -ne '\') { break }
      $e = $rest.IndexOfAny($sp); if ($e -lt 0) { $e = $rest.Length }
      $tok = $rest.Substring(0, $e); $rest = $rest.Substring($e); $prev = $tok
      if ($tok -ceq '\') { continue }
      if ($tok -cmatch '^[&|;)]' -or $tok -cmatch '^[0-9]*[<>]') { break }
      $val = $null
      if ($skip) { $skip = $false; $val = $tok; if ($flag -eq 'repo') { $repo = $val } }
      elseif ($tok -ceq '-R' -or $tok -ceq '--repo') { $skip = $true; $flag = 'repo'; continue }
      elseif ($tok -cin '-t', '--subject', '-b', '--body', '-F', '--body-file', '-A', '--author-email', '--match-head-commit') { $skip = $true; $flag = ''; continue }
      elseif ($tok.StartsWith('--repo=', $ord)) { $val = $tok.Substring(7); $repo = $val }
      elseif ($tok.StartsWith('-R', $ord) -and $tok.Length -gt 2) { $val = $tok.Substring(2) -replace '^=', ''; $repo = $val }
      elseif ($tok.StartsWith('-', $ord)) { $eq = $tok.IndexOf('=', $ord); if ($eq -lt 0) { continue }; $val = $tok.Substring($eq + 1) }
      else { if (-not $prArg) { $prArg = $tok }; continue }
      if ($val.Length -gt 0 -and ($val[0] -eq '"' -or $val[0] -eq "'") -and $val.IndexOf($val[0], 1) -lt 0) { break }
    }
  }

  # A bare statement reaches gh only when GH_REPO is already exported, so with
  # no export before it the cwd repo's PR is checked too ($two).
  $two = $false
  if (-not $repo -and $pm.Success) {
    $s = $cmd.Substring(0, $pm.Index); $exp = $false
    $ghv = '("[^"]*"|''[^'']*''|[^\s;&|()]+)'
    $g = [regex]::Match($s, '(?:^|[\s;&|(])GH_REPO=' + $ghv + '\s+(?:[A-Za-z_][A-Za-z0-9_]*=[^\s;&|()]*\s+)*(?:command\s+)?$')
    if ($g.Success) { $repo = $g.Groups[1].Value }
    else {
      while (($g = [regex]::Match($s, '(?:^|[;&|(\n])\s*(export\s+)?GH_REPO=' + $ghv + '(\s*(?:$|[;&|\n]))?')).Success) {
        if ($g.Groups[1].Success) { $repo = $g.Groups[2].Value; $exp = $true; $two = $false }
        elseif ($g.Groups[3].Success) { $repo = $g.Groups[2].Value; if (-not $exp) { $two = $true } }
        $s = $s.Substring($g.Index + $g.Length)
      }
    }
  }
  if ($repo) { $repo = $repo.Trim('"', "'") }
  if ($prArg) { $prArg = $prArg.Trim('"', "'") }

  # Review-Merge <repo-or-empty>: checks that repo's PR; returns (fail-open)
  # when the view fails, and never returns on deny.
  function Review-Merge([string]$r) {
    $viewArgs = @('pr', 'view')
    if ($prArg) { $viewArgs += $prArg }
    if ($r) { $viewArgs += '-R', $r }
    $viewJson = $null
    try {
      $viewJson = (& gh @viewArgs --json 'body,baseRefName' 2>$null) -join "`n"
      if ($LASTEXITCODE -ne 0) { return }
    } catch { return }
    if ([string]::IsNullOrWhiteSpace($viewJson)) { return }

    try { $view = $viewJson | ConvertFrom-Json -ErrorAction Stop } catch { return }
    $prBody = [string]$view.body
    if ($prBody.StartsWith([string][char]0xFEFF, $ord)) { $prBody = $prBody.Substring(1) }
    $prBase = $view.baseRefName

    if ($protected -and $prBase -ceq $protected) { return }

    if ([string]::IsNullOrEmpty($prBody)) {
      Deny "the PR's body (fetched via gh pr view) is empty, so the required '$heading' section can't be verified. Add the section to the PR body,"
    }

    if (-not (HeadingMatch $prBody $false)) { Deny "the PR body is missing the required '$heading' section. Add one before merging the PR," }
    CheckVerdict $prBody 'merging the PR' $false
    CheckFindings $prBody 'merging the PR' $false
  }
  Review-Merge $repo
  if ($two) { Review-Merge '' }
}

exit 0
