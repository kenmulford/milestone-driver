#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for read-doc-section.ps1 (issue #184).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'read-doc-section.ps1'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

$pass = 0; $fail = 0
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rds_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
  $doc = Join-Path $tmp 'sample.md'
  $fixture = @'
# Title

Intro prose.

## Keys

Keys body line 1.

### Sub

Nested deeper than ## - stays inside Keys.

## Other

Other body.

## Keys

Duplicate Keys - must NOT be reached (first-match policy).

## Last

Last body, runs to EOF.
'@
  [System.IO.File]::WriteAllText($doc, ($fixture -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

  function Check([string]$name, [int]$wantExit, [string]$wantOut, [string[]]$cliArgs) {
    $errFile = New-TemporaryFile
    $out = (& pwsh -NoProfile -File $script @cliArgs 2> $errFile.FullName)
    $rc = $LASTEXITCODE
    if ($out -is [array]) { $out = ($out -join "`n") }
    $out = ("$out") -replace '\r?\n$', ''
    $err = (Get-Content $errFile.FullName -Raw)
    if ($null -eq $err) { $err = '' }
    Remove-Item $errFile.FullName -Force
    if ($wantOut -eq '__FAIL__') {
      if ($rc -ne 0 -and [string]::IsNullOrEmpty($out) -and -not [string]::IsNullOrEmpty($err)) {
        $script:pass++
      } else {
        $script:fail++
        Write-Host "FAIL $name rc=$rc out=[$out] err=[$err] (want nonzero rc, empty out, nonempty err)"
      }
    } else {
      if ($rc -eq $wantExit -and $out -eq $wantOut) {
        $script:pass++
      } else {
        $script:fail++
        Write-Host "FAIL $name rc=$rc(want $wantExit)`n--- got ---`n$out`n--- want ---`n$wantOut`n--- err ---`n$err"
      }
    }
  }

  $wantKeys = @'
## Keys

Keys body line 1.

### Sub

Nested deeper than ## - stays inside Keys.
'@ -replace "`r`n", "`n"
  Check 'happy' 0 $wantKeys @($doc, 'Keys')

  $wantLast = @'
## Last

Last body, runs to EOF.
'@ -replace "`r`n", "`n"
  Check 'eof' 0 $wantLast @($doc, 'Last')

  Check 'missing-anchor' 1 '__FAIL__' @($doc, 'DoesNotExist')

  Check 'missing-file' 1 '__FAIL__' @((Join-Path $tmp 'nope.md'), 'Keys')

  Check 'usage' 2 '__FAIL__' @($doc)
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "read-doc-section.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
