#!/usr/bin/env pwsh
# milestone-driver - clear one issue's dispatch-cap counters at park time, so a
# re-run after the park starts a fresh chain.
# Usage: reset-dispatch-cap.ps1 <repo-root> <n>
# pwsh twin of reset-dispatch-cap.sh (rules, output, and exit codes documented there).
Set-StrictMode -Version Latest

function Err([string]$msg) { [Console]::Error.WriteLine($msg) }

if ($args.Count -ne 2) {
  Err 'usage: reset-dispatch-cap.ps1 <repo-root> <n>'
  exit 2
}
$root = ([string]$args[0]) -replace '\\', '/'
$n = [string]$args[1]
if ($n -notmatch '^[0-9]+$') {
  Err "reset-dispatch-cap: <n> must be digits: $n"
  exit 2
}

$removed = 0
if (Get-Command git -ErrorAction SilentlyContinue) {
  $common = & git -C $root rev-parse --git-common-dir 2>$null
  if ($LASTEXITCODE -eq 0 -and $common) {
    $common = ([string]$common) -replace '\\', '/'
    if (-not [System.IO.Path]::IsPathRooted($common)) { $common = Join-Path $root $common }
    foreach ($kind in @('review', 'implementer', 'planner')) {
      $f = Join-Path $common 'milestone-driver' 'dispatch-cap' "$kind-$n"
      if (Test-Path -LiteralPath $f -PathType Leaf) {
        try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop; $removed++ } catch { }
      }
    }
  }
}

# LF, not the host newline: byte parity with the .sh twin.
[Console]::Out.Write("reset`t$n`t$removed`n")
exit 0
