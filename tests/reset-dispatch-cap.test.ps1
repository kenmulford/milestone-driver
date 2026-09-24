#!/usr/bin/env pwsh
# milestone-driver - behavior runner for scripts/reset-dispatch-cap (the park-time counter reset).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here '_lib.ps1'); Set-Leg $Leg
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Script = Join-Path $Root 'scripts' 'reset-dispatch-cap'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mdr_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Ok { $script:pass++ }
function No([string]$msg) { $script:fail++; Write-Host "FAIL $msg" }
function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

function New-Repo {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $w | Out-Null
  & git -C $w init -q 2>$null | Out-Null
  & git -C $w config core.hooksPath (Join-Path $w '.git' 'no-such-hooks') 2>$null | Out-Null
  & git -C $w config commit.gpgsign false 2>$null | Out-Null
  & git -C $w config user.email 'tests@milestone-driver.invalid' 2>$null | Out-Null
  & git -C $w config user.name 'reset-dispatch-cap tests' 2>$null | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $w 'README.md'), "seed`n", $utf8)
  & git -C $w add -A 2>$null | Out-Null
  & git -C $w commit -q -m base 2>$null | Out-Null
  return $w
}

function Add-Counters([string]$repo, [string[]]$names) {
  $dir = Join-Path $repo '.git' 'milestone-driver' 'dispatch-cap'
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  foreach ($n in $names) { [System.IO.File]::WriteAllText((Join-Path $dir $n), "abc 2`n", $utf8) }
  return $dir
}

function Expect-Out([string]$label, $r, [string]$want) {
  if ($r.rc -eq 0 -and $r.out -ceq $want -and [string]::IsNullOrEmpty($r.err)) { Ok }
  else { No "${label}: rc=$($r.rc) out=[$(Show-Escaped $r.out)] want=[$(Show-Escaped $want)] err=[$(Show-Escaped $r.err)]" }
}

function Expect-Present([string]$label, [string]$dir, [string[]]$gone, [string[]]$kept) {
  $bad = @()
  foreach ($n in $gone) { if (Test-Path -LiteralPath (Join-Path $dir $n)) { $bad += "still:$n" } }
  foreach ($n in $kept) { if (-not (Test-Path -LiteralPath (Join-Path $dir $n))) { $bad += "lost:$n" } }
  if ($bad.Count -eq 0) { Ok } else { No "${label}: $($bad -join ' ')" }
}

$Seven = @('review-7', 'implementer-7', 'planner-7')
$Seventy = @('review-70', 'implementer-70', 'planner-70', 'review-develop')

try {
  # ---- only the named issue's three counters go ----------------------------
  $R = New-Repo
  $dir = Add-Counters $R ($Seven + $Seventy)
  Expect-Out 'reset-7' (Invoke-Leg -Script $Script -Args @($R, '7') -Cwd $Tmp) "reset`t7`t3`n"
  Expect-Present 'reset-7-files' $dir $Seven $Seventy

  # ---- a partial set counts only what it removed ----------------------------
  [void](Add-Counters $R @('planner-7'))
  Expect-Out 'reset-7-partial' (Invoke-Leg -Script $Script -Args @($R, '7') -Cwd $Tmp) "reset`t7`t1`n"

  # ---- a linked worktree resolves the shared common dir ----------------------
  $RW = New-Repo
  $wt = Join-Path $Tmp ([System.Guid]::NewGuid().ToString('N'))
  & git -C $RW worktree add -q -b issue/7-x $wt 2>$null | Out-Null
  $dirW = Add-Counters $RW ($Seven + $Seventy)
  Expect-Out 'reset-in-worktree' (Invoke-Leg -Script $Script -Args @($wt, '7') -Cwd $Tmp) "reset`t7`t3`n"
  Expect-Present 'reset-in-worktree-files' $dirW $Seven $Seventy

  # ---- fail-open: no counter directory, no repo -----------------------------
  $RE = New-Repo
  Expect-Out 'absent-dir' (Invoke-Leg -Script $Script -Args @($RE, '7') -Cwd $Tmp) "reset`t7`t0`n"
  $plain = Join-Path $Tmp ([System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $plain | Out-Null
  Expect-Out 'no-repo' (Invoke-Leg -Script $Script -Args @($plain, '7') -Cwd $Tmp) "reset`t7`t0`n"

  # ---- bad usage exits 2 with nothing on stdout -----------------------------
  foreach ($case in @(@('usage-none', @()), @('usage-one', @($R)), @('usage-nondigit', @($R, '7a')),
      @('usage-empty-n', @($R, '')), @('usage-three', @($R, '7', 'x')))) {
    $r = Invoke-Leg -Script $Script -Args $case[1] -Cwd $Tmp
    if ($r.rc -eq 2 -and [string]::IsNullOrEmpty($r.out) -and -not [string]::IsNullOrEmpty($r.err)) { Ok }
    else { No "$($case[0]): rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }
  }
}
finally {
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "reset-dispatch-cap ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
