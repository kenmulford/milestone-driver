#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for assemble-common.ps1 (issue #692).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/assemble-common'
$rds = Join-Path $root 'scripts/read-doc-section'
$fixRoot = Join-Path $root 'tests/fixtures/assemble-common'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$pass = 0; $fail = 0
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("asc_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

function Ok([string]$name, [bool]$cond, [string]$detail) {
  if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name $detail" }
}
function Section([string]$doc, [string]$heading) {
  $r = Invoke-Leg -Script $rds -Args @($doc, $heading)
  if ($r.rc -ne 0) { throw "fixture read failed: $heading in $doc" }
  return $r.out.TrimEnd("`n")
}
# A fresh output directory per case, so "no file written" is checkable as "dir empty".
function New-CaseDir([string]$name) {
  $d = Join-Path $tmp $name
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  return $d
}

try {
  # The expected prefix is built from read-doc-section (covered by its own suite)
  # so these cases pin assembly order and separators, not the style text itself.
  $style = Join-Path $root 'skills/output-style.md'
  $parts = foreach ($h in @('GitHub-facing prose', 'When prose is the correct form', 'Evidence slots', 'The two anti-criteria')) {
    Section $style $h
  }
  $cite = [System.IO.File]::ReadAllText((Join-Path $root 'skills/citation-format.md'), $utf8).TrimEnd("`n")
  $prefix = ($parts -join "`n`n") + "`n`n" + $cite
  $alpha = "## Alpha`n`nAlpha body.`n`n### Alpha detail`n`nNested under Alpha."
  $build = "## Build (fast path)`n`nBuild body, runs to EOF."

  # Cwd is the case dir, not the fixture root: the doc must resolve against <repo-root>.
  $d = New-CaseDir 'two-anchors'
  $outFile = Join-Path $d 'common.md'
  $r = Invoke-Leg -Script $script -Cwd $d -Args @($fixRoot, $outFile, 'standing.md#Build (fast path)', 'standing.md#Alpha')
  $want = $prefix + "`n`n" + $build + "`n`n" + $alpha + "`n"
  $got = if (Test-Path -LiteralPath $outFile) { [System.IO.File]::ReadAllText($outFile, $utf8) } else { '<no file>' }
  Ok 'two-anchors' ($r.rc -eq 0 -and $got -ceq $want) "rc=$($r.rc) err=[$($r.err)]`n--- got tail ---`n$($got.Substring([Math]::Max(0, $got.Length - 300)))"
  $bytes = if (Test-Path -LiteralPath $outFile) { [System.IO.File]::ReadAllBytes($outFile) } else { [byte[]]@() }
  Ok 'no-bom' ($bytes.Length -ge 3 -and -not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'output starts with a BOM or is empty'
  Ok 'two-anchors-no-temp' (@(Get-ChildItem -LiteralPath $d).Count -eq 1) "leftover files: $(@(Get-ChildItem -LiteralPath $d -Name) -join ',')"

  $d = New-CaseDir 'zero-anchors'
  $outFile = Join-Path $d 'common.md'
  $r = Invoke-Leg -Script $script -Args @($fixRoot, $outFile)
  $got = if (Test-Path -LiteralPath $outFile) { [System.IO.File]::ReadAllText($outFile, $utf8) } else { '<no file>' }
  Ok 'zero-anchors' ($r.rc -eq 0 -and $got -ceq ($prefix + "`n")) "rc=$($r.rc) err=[$($r.err)]"

  # Missing heading, unreadable doc: rc 1, stderr names the anchor and the doc, nothing written.
  foreach ($c in @(
      @{ name = 'missing-heading'; anchor = 'standing.md#Gamma'; heading = 'Gamma'; doc = 'standing.md' },
      @{ name = 'missing-doc'; anchor = 'nope.md#Alpha'; heading = 'Alpha'; doc = 'nope.md' })) {
    $d = New-CaseDir $c.name
    $outFile = Join-Path $d 'common.md'
    $r = Invoke-Leg -Script $script -Args @($fixRoot, $outFile, 'standing.md#Alpha', $c.anchor)
    $empty = @(Get-ChildItem -LiteralPath $d).Count -eq 0
    Ok $c.name ($r.rc -eq 1 -and $empty -and $r.err -like "*$($c.heading)*" -and $r.err -like "*$($c.doc)*") "rc=$($r.rc) empty=$empty err=[$($r.err)]"
  }

  $d = New-CaseDir 'keeps-existing'
  $outFile = Join-Path $d 'common.md'
  [System.IO.File]::WriteAllText($outFile, "old`n", $utf8)
  $r = Invoke-Leg -Script $script -Args @($fixRoot, $outFile, 'standing.md#Gamma')
  $got = [System.IO.File]::ReadAllText($outFile, $utf8)
  Ok 'keeps-existing' ($r.rc -eq 1 -and $got -ceq "old`n" -and @(Get-ChildItem -LiteralPath $d).Count -eq 1) "rc=$($r.rc) got=[$got]"

  $d = New-CaseDir 'usage'
  $r = Invoke-Leg -Script $script -Cwd $d -Args @($fixRoot)
  Ok 'usage' ($r.rc -eq 2 -and $r.err -like '*usage*' -and @(Get-ChildItem -LiteralPath $d).Count -eq 0) "rc=$($r.rc) err=[$($r.err)]"

  $d = New-CaseDir 'no-hash'
  $outFile = Join-Path $d 'common.md'
  $r = Invoke-Leg -Script $script -Args @($fixRoot, $outFile, 'standing.md')
  Ok 'no-hash' ($r.rc -eq 2 -and $r.err -like '*standing.md*' -and @(Get-ChildItem -LiteralPath $d).Count -eq 0) "rc=$($r.rc) err=[$($r.err)]"

  # Parity needs both interpreters; the sh leg is the one that guarantees bash.
  if ($Leg -eq 'sh') {
    $got = @{}
    foreach ($l in @('sh', 'ps1')) {
      Set-Leg $l
      $outFile = Join-Path (New-CaseDir "parity-$l") 'common.md'
      $null = Invoke-Leg -Script $script -Args @($fixRoot, $outFile, 'standing.md#Alpha', 'standing.md#Build (fast path)')
      $got[$l] = if (Test-Path -LiteralPath $outFile) { [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($outFile)) } else { '' }
    }
    Set-Leg $Leg
    Ok 'legs-byte-identical' ($got['sh'] -ne '' -and $got['sh'] -ceq $got['ps1']) "sh=$($got['sh'].Length) ps1=$($got['ps1'].Length) (base64 chars)"
  }
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "assemble-common ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
