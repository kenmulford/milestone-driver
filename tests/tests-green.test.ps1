#!/usr/bin/env pwsh
# milestone-driver - runner for the tests-green.ps1 hook (issue #499).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Hook = Join-Path $Root 'hooks' 'tests-green.ps1'
$RepoGitignore = Join-Path $Root '.milestone-config' '.gitignore'
if (-not (Test-Path -LiteralPath $Hook)) { Write-Error "FATAL: missing $Hook"; exit 3 }
if (-not (Test-Path -LiteralPath $RepoGitignore)) { Write-Error "FATAL: missing $RepoGitignore"; exit 3 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }
$Hook = (Resolve-Path $Hook).Path
$pwshBin = (Get-Command pwsh).Source

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Ok { $script:pass++ }
function No([string]$msg) { $script:fail++; Write-Host "FAIL $msg" }

function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

function New-Workspace([string]$globsJson = '["src/**"]', [string]$stagedPath = 'src/a.txt') {
  $w = Join-Path $Tmp ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $w | Out-Null
  git -C $w init -q
  git -C $w config user.email tests-green@example.invalid
  git -C $w config user.name tests-green
  New-Item -ItemType Directory -Path (Join-Path $w '.milestone-config') | Out-Null
  $staged = Join-Path $w $stagedPath
  New-Item -ItemType Directory -Path (Split-Path -Parent $staged) -Force | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $w '.milestone-config' 'driver.json'),
    '{"unitTestCmd":"git --version","sourceGlobs":' + $globsJson + '}' + "`n", $utf8)
  [System.IO.File]::WriteAllText($staged, "x`n", $utf8)
  git -C $w add $stagedPath
  return $w
}

function Invoke-Hook([string]$root) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $pwshBin
  foreach ($a in @('-NoProfile', '-File', $Hook)) { [void]$psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $Tmp
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardInputEncoding = $utf8
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $payload = @{ tool_input = @{ command = 'git commit -m x' }; cwd = $root } | ConvertTo-Json -Compress
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($payload)
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{
    out = $outTask.GetAwaiter().GetResult()
    err = $errTask.GetAwaiter().GetResult()
    rc  = $p.ExitCode
  }
}

# ---- self-healed .gitignore is byte-identical to the committed one ----------
$W = New-Workspace
$r = Invoke-Hook $W
$emitted = Join-Path $W '.milestone-config' '.gitignore'
if ($r.rc -ne 0) { No "gitignore-emitted: hook rc=$($r.rc) err=[$(Show-Escaped $r.err)]" }
elseif (-not (Test-Path -LiteralPath $emitted)) {
  No "gitignore-emitted: hook wrote no $emitted (err=[$(Show-Escaped $r.err)])"
}
else {
  $a = [System.IO.File]::ReadAllBytes($emitted)
  $b = [System.IO.File]::ReadAllBytes($RepoGitignore)
  if ([System.Linq.Enumerable]::SequenceEqual($a, $b)) { Ok }
  else { No "gitignore-emitted: differs from $RepoGitignore ($($a.Length) vs $($b.Length) bytes)" }
}

# ---- an EXISTING .gitignore is never rewritten ------------------------------
$W = New-Workspace
[System.IO.File]::WriteAllBytes((Join-Path $W '.milestone-config' '.gitignore'), $utf8.GetBytes("sentinel`n"))
$r = Invoke-Hook $W
$kept = [System.IO.File]::ReadAllText((Join-Path $W '.milestone-config' '.gitignore'), $utf8)
if ($r.rc -eq 0 -and [string]::Equals($kept, "sentinel`n", [System.StringComparison]::Ordinal)) { Ok }
else { No "gitignore-preserved: rc=$($r.rc) content=[$(Show-Escaped $kept)] err=[$(Show-Escaped $r.err)]" }

# ---- a globstar-prefix glob does not match a root-level staged path --------
$W = New-Workspace '["**/*.md"]' 'x.md'
$r = Invoke-Hook $W
if ($r.rc -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' '.gitignore'))) { Ok }
else { No "globstar-root: rc=$($r.rc) (want 0) and the hook must not reach its post-green write, err=[$(Show-Escaped $r.err)]" }

if (-not $IsWindows) { chmod -R u+w $Tmp 2>$null }
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
Write-Host "tests-green.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
