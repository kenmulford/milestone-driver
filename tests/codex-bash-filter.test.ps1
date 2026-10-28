#!/usr/bin/env pwsh
# milestone-driver - Codex has no `if` pre-filter, so every Bash-matched gate
# sees every Bash command. Each gate passes a non-matching command and still
# blocks its matching control under the same profile.
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1'); Set-Leg $Leg
$root = Split-Path $PSScriptRoot -Parent
$utf8 = [Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('milestone-driver-bash-filter-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path "$tmp/.milestone-config", "$tmp/src" -Force | Out-Null
git -C $tmp init -q -b main
git -C $tmp config user.email bash-filter@example.invalid
git -C $tmp config user.name bash-filter
[IO.File]::WriteAllText("$tmp/.milestone-config/driver.json", '{"protectedBranch":"main","integrationBranch":"develop","sourceGlobs":["src/**"],"unitTestCmd":"git not-a-real-subcommand"}', $utf8)
[IO.File]::WriteAllText("$tmp/src/a.txt", "x`n", $utf8)
git -C $tmp add src/a.txt
foreach ($v in 'TESTS_GREEN', 'NO_PUSH', 'CODE_REVIEW_GATE') { [Environment]::SetEnvironmentVariable("CLAUDE_HOOK_DISABLE_$v", $null) }

function Check([string]$gate, [string]$command, [int]$want) {
  $payload = @{ tool_name = 'Bash'; cwd = $tmp; tool_input = @{ command = $command } } | ConvertTo-Json -Compress
  # Out of process: in-process, tests-green's script-scope $LASTEXITCODE reset shadows the native exit code.
  $r = Invoke-Spawn -Script "$root/hooks/$gate" -Stdin $payload -Cwd $tmp
  if ($r.rc -eq $want) { $script:pass++ }
  else { $script:fail++; Write-Host "FAIL $gate [$command]: rc=$($r.rc) want=$want err=[$($r.err)]" }
}
try {
  foreach ($cmd in 'git status', 'ls src', 'echo git') {
    foreach ($gate in 'tests-green', 'no-push', 'no-pr-to-protected', 'code-review-gate') { Check $gate $cmd 0 }
  }
  Check tests-green 'gh pr create --base develop' 0
  Check no-push 'git commit -m x' 0
  Check no-pr-to-protected 'gh pr view 1' 0
  Check code-review-gate 'gh pr view 1' 0
  Check tests-green 'git commit -m x' 2
  Check no-push 'git push origin main' 2
  Check no-pr-to-protected 'gh pr create --base main --title x' 2
  Check code-review-gate 'gh pr create --base develop --title x' 2
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force
}
Write-Host "codex-bash-filter ($Leg): $pass passed, $fail failed"
if ($fail) { exit 1 }
