#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for code-review-gate.ps1 (issue #289).
# Bash parity of code-review-gate.test.sh — drives the SAME
# tests/code-review-gate.cases.tsv and asserts the SAME exit code + stderr,
# proving the bash/pwsh twins behave identically. The stub `gh` written for
# the merge cases is a bash-shebang script (Linux-executable); CI runs both
# legs on ubuntu-latest (.github/workflows/ci.yml), which is what this proves
# — a native-Windows run of this file would need bash/WSL on PATH for the
# merge-verb stub cases, the same cross-platform-helper posture already used
# by tests/render-daemon.test.sh (python3 stub server).
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script = Join-Path $Here '../hooks/code-review-gate.ps1'
$Cases = Join-Path $Here 'code-review-gate.cases.tsv'
if (-not (Test-Path $Script)) { Write-Error "FATAL: missing $Script"; exit 3 }
$pwshBin = (Get-Command pwsh).Source

$pass = 0; $fail = 0
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Unescape([string]$s) {
  if ($null -eq $s) { return '' }
  return ($s -replace '\\n', "`n")
}

function New-GhStub([string]$mode, [string]$json) {
  $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $dir | Out-Null
  switch ($mode) {
    'NOGH' {
      # No gh stub at all -> caller sets PATH to just this (gh-less) dir.
    }
    'ERROR' {
      Set-Content -Path (Join-Path $dir 'gh') -Value "#!/usr/bin/env bash`nexit 1`n" -NoNewline -Encoding utf8NoBOM
      & chmod +x (Join-Path $dir 'gh')
    }
    'OK' {
      $jsonPath = Join-Path $dir 'view.json'
      Set-Content -Path $jsonPath -Value $json -NoNewline -Encoding utf8NoBOM
      $ghScript = "#!/usr/bin/env bash`nif [ `"`$1`" = `"pr`" ] && [ `"`$2`" = `"view`" ]; then cat '$jsonPath'; exit 0; fi`nexit 1`n"
      Set-Content -Path (Join-Path $dir 'gh') -Value $ghScript -NoNewline -Encoding utf8NoBOM
      & chmod +x (Join-Path $dir 'gh')
    }
  }
  return $dir
}

function Pass-T() { $script:pass++ }
function Fail-T([string]$name, $rc, $wantExit, [string]$err, [string]$wantErr, [string]$out) {
  $script:fail++
  Write-Error "FAIL $name`: rc=$rc (want $wantExit) stderr=[$err] (want [$wantErr]) stdout=[$out]" -ErrorAction Continue
}

$rows = Get-Content $Cases
foreach ($row in $rows) {
  if ($row -eq '' -or $row.StartsWith('#')) { continue }
  $cols = $row -split "`t"
  $name = $cols[0]; $verb = $cols[1]; $commandRaw = $cols[2]
  $bodyfileContent = if ($cols.Count -gt 3) { $cols[3] } else { '' }
  $ghMode = if ($cols.Count -gt 4) { $cols[4] } else { '' }
  $ghViewBody = if ($cols.Count -gt 5) { $cols[5] } else { '' }
  $ghViewBase = if ($cols.Count -gt 6) { $cols[6] } else { '' }
  $protected = if ($cols.Count -gt 7 -and $cols[7]) { $cols[7] } else { 'main' }
  $disableEnv = if ($cols.Count -gt 8) { $cols[8] } else { '' }
  $wantExit = if ($cols.Count -gt 9 -and $cols[9]) { [int]$cols[9] } else { 0 }
  $wantStderr = if ($cols.Count -gt 10) { $cols[10] } else { '' }

  $cmd = Unescape $commandRaw

  if ($cmd -like '*__BODYFILE_REL__*') {
    $rel = "$name-body.md"
    Set-Content -Path (Join-Path $Tmp $rel) -Value (Unescape $bodyfileContent) -NoNewline -Encoding utf8NoBOM
    $cmd = $cmd.Replace('__BODYFILE_REL__', $rel)
  } elseif ($cmd -like '*__BODYFILE_ABS__*') {
    $abs = Join-Path $Tmp "$name-body-abs.md"
    Set-Content -Path $abs -Value (Unescape $bodyfileContent) -NoNewline -Encoding utf8NoBOM
    $cmd = $cmd.Replace('__BODYFILE_ABS__', $abs)
  }

  $mcDir = Join-Path $Tmp '.milestone-config'
  New-Item -ItemType Directory -Path $mcDir -Force | Out-Null
  (@{ protectedBranch = $protected } | ConvertTo-Json -Compress) | Set-Content -Path (Join-Path $mcDir 'driver.json') -NoNewline -Encoding utf8NoBOM

  $jsonIn = @{ tool_input = @{ command = $cmd }; cwd = $Tmp } | ConvertTo-Json -Compress

  $origPath = $env:PATH
  $stubDir = $null
  if ($verb -eq 'merge' -and $ghMode) {
    $viewJson = @{ body = (Unescape $ghViewBody); baseRefName = $ghViewBase } | ConvertTo-Json -Compress
    $stubDir = New-GhStub $ghMode $viewJson
    if ($ghMode -eq 'NOGH') { $env:PATH = $stubDir } else { $env:PATH = "$stubDir$([System.IO.Path]::PathSeparator)$origPath" }
  }

  if ($disableEnv -eq '1') { $env:CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE = '1' }

  $errFile = Join-Path $Tmp 'stderr.txt'
  $out = $jsonIn | & $pwshBin -NoProfile -File $Script 2>$errFile
  $rc = $LASTEXITCODE
  $err = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue)
  if ($null -eq $err) { $err = '' } else { $err = $err.TrimEnd("`r", "`n") }
  $out = if ($null -eq $out) { '' } else { ($out -join "`n") }

  $env:PATH = $origPath
  Remove-Item Env:\CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE -ErrorAction SilentlyContinue
  if ($stubDir) { Remove-Item -Recurse -Force $stubDir -ErrorAction SilentlyContinue }

  $wantErr = Unescape $wantStderr
  if ($rc -eq $wantExit -and $err -eq $wantErr -and $out -eq '') {
    Pass-T
  } else {
    Fail-T $name $rc $wantExit $err $wantErr $out
  }
}

# ---- bespoke case: missing jq -> N/A for pwsh (native JSON, no jq dependency)
# The pwsh twin never shells out to jq, so there is no equivalent fail-open
# path to prove here — parity is about IDENTICAL observable behavior for every
# case the TWO IMPLEMENTATIONS SHARE, not about mirroring an implementation
# detail (jq) that only one twin has. See code-review-gate.ps1's ConvertFrom-Json
# try/catch for its own fail-open-on-parse-error path (exercised by every
# TSV row's ordinary JSON, which is why no dedicated row is needed).

Write-Output "code-review-gate.ps1: $pass passed, $fail failed"
if ($fail -eq 0) { exit 0 } else { exit 1 }
