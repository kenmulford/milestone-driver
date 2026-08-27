#!/usr/bin/env pwsh
# milestone-driver - run every tests/*.test.ps1 for one leg; exit 1 if any fails.
# run-all.ps1 [-Leg ps1|sh] [-Only a,b] [-Skip a,b]
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1', [string[]]$Only = @(), [string[]]$Skip = @())
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$failed = @()
foreach ($t in Get-ChildItem -LiteralPath $here -Filter '*.test.ps1' | Sort-Object Name) {
  $name = $t.Name -replace '\.test\.ps1$', ''
  if ($Only.Count -gt 0 -and $name -notin $Only) { continue }
  if ($name -in $Skip) { continue }
  & pwsh -NoProfile -File $t.FullName -Leg $Leg
  if ($LASTEXITCODE -ne 0) { $failed += $name }
}
if ($failed.Count -gt 0) { Write-Host "run-all ($Leg): FAILED $($failed -join ', ')"; exit 1 }
Write-Host "run-all ($Leg): all suites passed"
