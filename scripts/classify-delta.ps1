#!/usr/bin/env pwsh
# milestone-driver - comment-only delta classifier (issue #476).
# Behavior-identical pwsh sibling of scripts/classify-delta.sh. That file's
# header carries the full design rationale: why the delta is read against HEAD
# and not the index, why untracked files are checked first, why the
# header-versus-content split is POSITIONAL rather than prefix-based, why the
# +/- marker is stripped exactly one character before the prefix test, why a
# comment token must sit at column 0, why content is counted per file rather
# than across the delta, why a rename and a deletion are not comment edits, why
# a .sh file carrying a heredoc resolves the blunt way, why a block comment
# closing mid-line takes the safe branch, and why the prefix mapping is
# per-extension instead of a flat cross-language set.
#
# Usage:   classify-delta.ps1 [REPO_ROOT]
# Output:  stdout is one newline-terminated verdict, `comment-only` or
#          `code-changed`. stderr carries a single reason token, and only when
#          the verdict is code-changed: untracked:<path>, no-delta,
#          empty-delta, binary, unmapped-ext:<path>, deleted:<path>,
#          rename:<path>, mode:<path>, heredoc:<path>, directive:<path>,
#          code:<path>, no-content:<path>, or no-content. Exit is ALWAYS 0;
#          the verdict is the output, not the exit code.
param(
  [string]$Root = (Get-Location).Path
)
# Continue, not Stop: git writes to stderr on an ordinary non-repo root, and
# that is a classification input here, not a failure.
$ErrorActionPreference = 'Continue'
# Force UTF-8 stdout (no BOM) so output is byte-identical to the .sh sibling.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Root = ($Root -replace '/+$', '')

function Emit([string]$verdict, [string]$reason) {
  [Console]::Out.Write($verdict + "`n")
  if (-not [string]::IsNullOrEmpty($reason)) { [Console]::Error.Write($reason) }
  exit 0
}

# Get-Prefixes <lowercased-ext> -> the extension's comment prefixes, or $null
# when the extension is not mapped.
function Get-Prefixes([string]$ext) {
  switch ($ext) {
    { $_ -ceq 'sh' -or $_ -ceq 'py' -or $_ -ceq 'rb' } { return @('#') }
    { $_ -ceq 'ps1' } { return @('#', '<#', '#>') }
    { $_ -ceq 'md' }  { return @('<!--', '-->') }
    { $_ -ceq 'cs' -or $_ -ceq 'js' -or $_ -ceq 'ts' -or $_ -ceq 'go' } { return @('//', '/*', '*/') }
    { $_ -ceq 'sql' } { return @('--', '/*', '*/') }
  }
  return $null
}

# Get-BlockTokens <lowercased-ext> -> @(open, close) for the extensions that
# have a block comment form, or $null. Both tokens can open a line: "<# c #>
# code" and "#> code" are the same defect.
function Get-BlockTokens([string]$ext) {
  switch ($ext) {
    { $_ -ceq 'ps1' } { return @('<#', '#>') }
    { $_ -ceq 'md' }  { return @('<!--', '-->') }
    { $_ -ceq 'cs' -or $_ -ceq 'js' -or $_ -ceq 'ts' -or $_ -ceq 'go' -or $_ -ceq 'sql' } { return @('/*', '*/') }
  }
  return $null
}

# Get-Ext <path> -> the lowercased extension, or $null when the basename
# carries none. Splits on '/' only, matching the sh sibling's ${1##*/}: diff
# paths are always slash-separated.
function Get-Ext([string]$path) {
  $base = $path
  $i = $base.LastIndexOf('/')
  if ($i -ge 0) { $base = $base.Substring($i + 1) }
  $d = $base.LastIndexOf('.')
  if ($d -lt 0) { return $null }
  $e = $base.Substring($d + 1)
  if ($e.Length -eq 0) { return $null }
  return $e.ToLowerInvariant()
}

function Remove-AbPrefix([string]$p) {
  if ($p.StartsWith('a/', [StringComparison]::Ordinal) -or
      $p.StartsWith('b/', [StringComparison]::Ordinal)) { return $p.Substring(2) }
  return $p
}

# Machine-read directives. Checked BEFORE the comment test and without regard
# to the file's extension. When a directive's last character is alphanumeric,
# the next source character must be absent or a non-word character, so
# "#if DEBUG" matches while a prose comment "#iffy" does not; otherwise the
# directive is its own boundary. Ordinal / -cmatch throughout, mirroring the
# sh sibling's LC_ALL=C byte ranges.
$script:Directives = @(
  '#!', '# shellcheck', '# frozen_string_literal', '# type:', '# noqa',
  '// @ts-', '// eslint-', '//go:build', '#pragma', '#if', '#region', '#endif'
)
function Test-Directive([string]$s) {
  foreach ($d in $script:Directives) {
    if (-not $s.StartsWith($d, [StringComparison]::Ordinal)) { continue }
    $last = $d.Substring($d.Length - 1)
    if ($last -cmatch '^[0-9A-Za-z]$') {
      $rest = $s.Substring($d.Length)
      if ($rest.Length -eq 0 -or ($rest.Substring(0, 1) -cnotmatch '^[0-9A-Za-z_]$')) { return $true }
    } else {
      return $true
    }
  }
  return $false
}

function Test-Comment([string]$s, [string[]]$prefixes) {
  foreach ($p in $prefixes) {
    if ($s.StartsWith($p, [StringComparison]::Ordinal)) { return $true }
  }
  return $false
}

# Test-ClosesBlockThenCode -> $true when the line opens with the file's block
# open or close token, that block closes before end of line, and something
# other than whitespace follows the closing token.
function Test-ClosesBlockThenCode([string]$s, [string]$open, [string]$close) {
  if ([string]::IsNullOrEmpty($close)) { return $false }
  if (-not ($s.StartsWith($open, [StringComparison]::Ordinal) -or
            $s.StartsWith($close, [StringComparison]::Ordinal))) { return $false }
  $i = $s.IndexOf($close, [StringComparison]::Ordinal)
  if ($i -lt 0) { return $false }
  $rest = $s.Substring($i + $close.Length)
  return ($rest -cmatch '\S')
}

# Test-Heredoc <path> -> $true when the working-tree file carries '<<'
# anywhere, or cannot be read at all. Deliberately blunt: '<<' also matches a
# left shift and a comment that names the operator, and both resolve to
# code-changed, which is the safe direction. An unreadable file is an
# uncertainty, so it resolves the same way.
function Test-Heredoc([string]$root, [string]$path) {
  $f = Join-Path $root $path
  try {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $true }
    $text = [System.IO.File]::ReadAllText($f)
  } catch {
    return $true
  }
  return $text.Contains('<<')
}

# ---- 1. untracked files, before anything else.
try {
  $untracked = @(& git -C $Root ls-files --others --exclude-standard 2>$null)
} catch {
  $untracked = @()
}
if ($untracked.Count -gt 0 -and -not [string]::IsNullOrEmpty($untracked[0])) {
  Emit 'code-changed' ('untracked:' + $untracked[0])
}

# ---- 2. the delta. The -c and -- flags pin the output shape against any
# repo/user config that would reshape it, and -M forces rename detection ON so
# a rename never decomposes into a delete plus an add.
try {
  $delta = @(& git -C $Root -c core.quotePath=false --no-pager diff -U0 --no-color `
    --no-ext-diff --no-textconv -M --src-prefix=a/ --dst-prefix=b/ HEAD 2>$null)
  $rc = $LASTEXITCODE
} catch {
  $rc = 1
}
if ($rc -ne 0) { Emit 'code-changed' 'no-delta' }
if ($delta.Count -eq 0) { Emit 'code-changed' 'empty-delta' }

# ---- 3. walk it.
$inHunk = $false
$aPath = ''
$curPath = ''
$curMapped = $false
$curExt = ''
$curHeredoc = ''
$curPrefixes = @()
$curBlockOpen = ''
$curBlockClose = ''
$blockOpen = $false
$blockPath = ''
$blockContent = 0
$verdict = ''
$reason = ''

foreach ($line in $delta) {
  # Content first, and only inside a hunk. This ordering is what keeps a
  # markdown "+---" or "++++ TOML" source line from being read as a file header.
  if ($inHunk -and ($line.StartsWith('+', [StringComparison]::Ordinal) -or
                    $line.StartsWith('-', [StringComparison]::Ordinal))) {
    $src = $line.Substring(1)
    $blockContent++
    if (Test-Directive $src) { $verdict = 'code-changed'; $reason = "directive:$curPath"; break }
    if (-not (Test-Comment $src $curPrefixes)) { $verdict = 'code-changed'; $reason = "code:$curPath"; break }
    if (Test-ClosesBlockThenCode $src $curBlockOpen $curBlockClose) {
      $verdict = 'code-changed'; $reason = "code:$curPath"; break
    }
    # Resolved once per file, and only on a line that would otherwise pass as a
    # comment, so a real code change keeps the more precise reason.
    if ($curExt -ceq 'sh') {
      if ($curHeredoc -ceq '') {
        $curHeredoc = if (Test-Heredoc $Root $curPath) { 'yes' } else { 'no' }
      }
      if ($curHeredoc -ceq 'yes') { $verdict = 'code-changed'; $reason = "heredoc:$curPath"; break }
    }
    continue
  }
  if ($line.StartsWith('diff --git ', [StringComparison]::Ordinal)) {
    # Close the block this header ends before opening the next one.
    if ($blockOpen -and $blockContent -eq 0) {
      $verdict = 'code-changed'; $reason = "no-content:$blockPath"; break
    }
    $inHunk = $false; $aPath = ''; $curPath = ''; $curMapped = $false
    $curExt = ''; $curHeredoc = ''; $curPrefixes = @()
    $curBlockOpen = ''; $curBlockClose = ''
    # Best-effort path for the reasons that fire before "+++" registers one. A
    # path holding a space truncates here; the verdict does not depend on it,
    # only the token does.
    $g = $line.Substring('diff --git '.Length)
    $sp = $g.IndexOf(' ', [StringComparison]::Ordinal)
    if ($sp -ge 0) { $g = $g.Substring(0, $sp) }
    $blockPath = Remove-AbPrefix $g
    $blockOpen = $true; $blockContent = 0
  } elseif ($line.StartsWith('Binary files ', [StringComparison]::Ordinal)) {
    $verdict = 'code-changed'; $reason = 'binary'; break
  } elseif ($line.StartsWith('old mode ', [StringComparison]::Ordinal) -or
            $line.StartsWith('new mode ', [StringComparison]::Ordinal)) {
    $verdict = 'code-changed'; $reason = "mode:$blockPath"; break
  } elseif ($line.StartsWith('--- ', [StringComparison]::Ordinal)) {
    $p = $line.Substring(4)
    if ($p -ceq '/dev/null') { $aPath = '' } else { $aPath = Remove-AbPrefix $p }
  } elseif ($line.StartsWith('+++ ', [StringComparison]::Ordinal)) {
    $p = $line.Substring(4)
    if ($p -ceq '/dev/null') { $verdict = 'code-changed'; $reason = "deleted:$aPath"; break }
    $newPath = Remove-AbPrefix $p
    if ($aPath -cne '' -and $aPath -cne $newPath) {
      $verdict = 'code-changed'; $reason = "rename:$newPath"; break
    }
    $curPath = $newPath
    $e = Get-Ext $curPath
    $pf = if ($null -eq $e) { $null } else { Get-Prefixes $e }
    if ($null -eq $pf) {
      $curMapped = $false; $curPrefixes = @(); $curExt = ''
    } else {
      $curMapped = $true; $curPrefixes = $pf; $curExt = $e
      $bt = Get-BlockTokens $e
      if ($null -ne $bt) { $curBlockOpen = $bt[0]; $curBlockClose = $bt[1] }
    }
    # The extension gate fires at registration, not at the first content line,
    # so an unmapped file that changed with no readable content still reports
    # why it is code-changed.
    if (-not $curMapped) { $verdict = 'code-changed'; $reason = "unmapped-ext:$curPath"; break }
  } elseif ($line.StartsWith('@@', [StringComparison]::Ordinal)) {
    $inHunk = $true
  }
}

if ($verdict -ne '') { Emit $verdict $reason }
if ($blockOpen) {
  if ($blockContent -eq 0) { Emit 'code-changed' "no-content:$blockPath" }
} else {
  Emit 'code-changed' 'no-content'
}
Emit 'comment-only' ''
