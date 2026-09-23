#!/usr/bin/env pwsh
# milestone-driver - assemble one common.md from the prose contract and standing anchors (issue #692).
# Usage: assemble-common.ps1 <repo-root> <out-file> [<doc>#<heading> ...]
# Writes <out-file> holding, in order: the four skills/output-style.md sections
# the implementer brief names, skills/citation-format.md whole, then each
# <doc>#<heading> argument's section via read-doc-section. Parts are separated by
# exactly one blank line, so each part's trailing newlines are dropped first.
# An argument splits on its FIRST '#'. <doc> is joined onto <repo-root>, never
# resolved against the cwd. The contract files are read from this script's own
# plugin install, since the signature carries no plugin-root argument.
# Fail-CLOSED and atomic: the file is built in a temp file beside <out-file> and
# moved into place only on success, so any failure leaves <out-file> as it was.
# Output bytes match the .sh twin: UTF-8 without BOM, LF line endings.
# Exit codes: 0 ok · 1 missing file / missing anchor / write failure · 2 bad usage.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Err([string]$msg) { [Console]::Error.WriteLine($msg) }

if ($args.Count -lt 2) {
  Err 'usage: assemble-common.ps1 <repo-root> <out-file> [<doc>#<heading> ...]'
  exit 2
}
$root = [string]$args[0]
$anchors = @($args | Select-Object -Skip 2 | ForEach-Object { [string]$_ })
foreach ($a in $anchors) {
  if (-not $a.Contains('#')) { Err "assemble-common: anchor argument has no '#': $a"; exit 2 }
}
# .NET file APIs resolve a relative path against the process cwd, which
# Set-Location does not move; resolve against the PowerShell location instead.
$out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath([string]$args[1])

$plugin = Split-Path -Parent $PSScriptRoot
$rds = Join-Path $PSScriptRoot 'read-doc-section.ps1'
$parts = [System.Collections.Generic.List[string]]::new()

# read-doc-section.ps1 writes through [Console]::Out, not the pipeline, so its
# section is captured by swapping the console writer; its stderr passes through.
function Read-Section([string]$doc, [string]$heading) {
  $old = [Console]::Out
  $sw = [System.IO.StringWriter]::new()
  $global:LASTEXITCODE = 0
  try { [Console]::SetOut($sw); $null = & $rds $doc $heading } finally { [Console]::SetOut($old) }
  if ($LASTEXITCODE -ne 0) { return $false }
  $parts.Add($sw.ToString().TrimEnd("`n"))
  return $true
}

foreach ($h in @('GitHub-facing prose', 'When prose is the correct form', 'Evidence slots', 'The two anti-criteria')) {
  if (-not (Read-Section "$plugin/skills/output-style.md" $h)) { exit 1 }
}
$citePath = "$plugin/skills/citation-format.md"
try {
  $parts.Add([System.IO.File]::ReadAllText($citePath, [System.Text.UTF8Encoding]::new($false)).TrimEnd("`n"))
} catch {
  Err "assemble-common: cannot read $citePath"
  exit 1
}
foreach ($a in $anchors) {
  $i = $a.IndexOf('#')
  $doc = $a.Substring(0, $i); $heading = $a.Substring($i + 1)
  if (-not (Read-Section "$root/$doc" $heading)) {
    Err "assemble-common: cannot resolve anchor '$a' in $root/$doc"
    exit 1
  }
}

$tmp = "$out.tmp.$PID"
try {
  [System.IO.File]::WriteAllText($tmp, ($parts -join "`n`n") + "`n", [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $tmp -Destination $out -Force
} catch {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Err "assemble-common: cannot write $out"
  exit 1
}
exit 0
