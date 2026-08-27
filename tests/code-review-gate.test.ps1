#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for code-review-gate.ps1 (issue #289).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here '_lib.ps1'); Set-Leg $Leg
$Script = Join-Path $Here '../hooks/code-review-gate'
$Cases = Join-Path $Here 'code-review-gate.cases.tsv'

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
      if ($Leg -eq 'sh') {
        foreach ($b in @('jq', 'cat')) {
          $c = Get-Command $b -CommandType Application -ErrorAction SilentlyContinue
          if ($c) { Copy-Item -LiteralPath $c.Source -Destination (Join-Path $dir (Split-Path -Leaf $c.Source)) }
        }
      }
    }
    'ERROR' {
      Set-Content -Path (Join-Path $dir 'gh') -Value "#!/usr/bin/env bash`nexit 1`n" -NoNewline -Encoding utf8NoBOM
      & chmod +x (Join-Path $dir 'gh')
      Set-Content -Path (Join-Path $dir 'gh.ps1') -Value "exit 1`n" -NoNewline -Encoding utf8NoBOM
    }
    'OK' {
      $jsonPath = Join-Path $dir 'view.json'
      Set-Content -Path $jsonPath -Value $json -NoNewline -Encoding utf8NoBOM
      $ghScript = "#!/usr/bin/env bash`nif [ `"`$1`" = `"pr`" ] && [ `"`$2`" = `"view`" ]; then cat '$jsonPath'; exit 0; fi`nexit 1`n"
      Set-Content -Path (Join-Path $dir 'gh') -Value $ghScript -NoNewline -Encoding utf8NoBOM
      & chmod +x (Join-Path $dir 'gh')
      $ghPs1 = "if (`$args.Count -ge 2 -and `$args[0] -eq 'pr' -and `$args[1] -eq 'view') { Get-Content -Raw -LiteralPath '$jsonPath'; exit 0 }`nexit 1`n"
      Set-Content -Path (Join-Path $dir 'gh.ps1') -Value $ghPs1 -NoNewline -Encoding utf8NoBOM
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

  $r = Invoke-Leg -Script $Script -Stdin $jsonIn -Cwd $Tmp
  $rc = $r.rc
  $err = $r.err.TrimEnd("`r", "`n")
  $out = $r.out

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

# ---- bespoke case: missing jq -> fail open (sh leg only; pwsh has no jq dependency)
if ($Leg -eq 'sh') {
  $nojq = Join-Path $Tmp 'nojq'
  New-Item -ItemType Directory -Path $nojq -Force | Out-Null
  $c = Get-Command cat -CommandType Application -ErrorAction SilentlyContinue
  if ($c) { Copy-Item -LiteralPath $c.Source -Destination (Join-Path $nojq (Split-Path -Leaf $c.Source)) }
  $rawJson = @{ tool_input = @{ command = 'gh pr create --base develop --title "x"' }; cwd = $Tmp } | ConvertTo-Json -Compress
  $r = Invoke-Leg -Script $Script -Stdin $rawJson -Cwd $Tmp -Env @{ PATH = $nojq }
  if ($r.rc -eq 0 -and $r.err -eq '' -and $r.out -eq '') { Pass-T } else { Fail-T 'missing_jq_failopen' $r.rc 0 $r.err '' $r.out }
}

Write-Output "code-review-gate ($Leg): $pass passed, $fail failed"
if ($fail -eq 0) { exit 0 } else { exit 1 }
