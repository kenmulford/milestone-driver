#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for measure-dispatch.ps1 (issue #693).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$script = Join-Path $here '..' 'scripts' 'measure-dispatch'
$fx = Join-Path $here 'fixtures' 'measure-dispatch'
$shape = '^\{"steps":[0-9]+(,"stepsBeforeFirstEdit":[0-9]+,"minutesToFirstEdit":[0-9.]+)?,"minutes":[0-9.]+\}$'

$pass = 0; $fail = 0
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mdp_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
  function Check([string]$name, [string]$wantOut, [string[]]$cliArgs, [hashtable]$envOverride = @{}, [int]$wantRc = -1) {
    $r = Invoke-Leg -Script $script -Args $cliArgs -Env $envOverride
    $rc = $r.rc; $raw = $r.out; $err = $r.err
    if ($wantOut -eq '__FAIL__') {
      if ($rc -ne 0 -and ($wantRc -lt 0 -or $rc -eq $wantRc) -and [string]::IsNullOrEmpty($raw) -and -not [string]::IsNullOrEmpty($err)) {
        $script:pass++
      } else {
        $script:fail++
        Write-Host "FAIL $name rc=$rc out=[$raw] err=[$err] (want rc $(if ($wantRc -lt 0) { 'nonzero' } else { $wantRc }), empty out, nonempty err)"
      }
      return
    }
    # Exact bytes, LF-terminated: the two legs must emit the identical line.
    if ($rc -eq 0 -and $raw -ceq ($wantOut + "`n") -and $wantOut -match $shape -and [string]::IsNullOrEmpty($err)) {
      $script:pass++
    } else {
      $script:fail++
      Write-Host "FAIL $name rc=$rc`n--- got ---`n[$raw]`n--- want ---`n[$wantOut]`n--- err ---`n$err"
    }
  }

  Check 'sample' '{"steps":5,"stepsBeforeFirstEdit":3,"minutesToFirstEdit":1.5,"minutes":4.2}' @((Join-Path $fx 'dispatch-sample.jsonl'))
  Check 'edit-first' '{"steps":2,"stepsBeforeFirstEdit":0,"minutesToFirstEdit":0.5,"minutes":3.2}' @((Join-Path $fx 'edit-first.jsonl'))
  # 27s = 0.45 min: a rounding midpoint, rounded half away from zero in both legs.
  Check 'no-edit' '{"steps":2,"minutes":0.5}' @((Join-Path $fx 'no-edit.jsonl'))
  Check 'zero-tool' '{"steps":0,"minutes":3}' @((Join-Path $fx 'zero-tool.jsonl'))

  $empty = Join-Path $tmp 'empty.jsonl'
  [System.IO.File]::WriteAllText($empty, '')
  Check 'empty-file' '{"steps":0,"minutes":0}' @($empty)

  function Write-Transcript([string]$name, [object[]]$calls) {
    $lines = foreach ($c in $calls) {
      $block = @{ type = 'tool_use'; id = 'b'; name = $c[1]; input = $c[2] }
      @{ type = 'assistant'; timestamp = $c[0]; message = @{ role = 'assistant'; content = @($block) } } | ConvertTo-Json -Compress -Depth 6
    }
    $path = Join-Path $tmp $name
    [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    return $path
  }
  $ts = '2026-09-23T10:00:00Z'
  $bashEdits = @("sed -i '' 's/a/b/' /repo/a.sh", "perl -i -pe 's/a/b/' /repo/a.sh", 'printf x | tee /repo/a.log',
    'echo x > /repo/a.txt', 'echo x >>/repo/a.txt', 'cmd 2>/dev/null > out.txt')
  $bashReads = @('ls > /dev/null', 'cmd 2>&1', 'cmd >&2', 'grep x f 2>/dev/null', 'ls >> /dev/null',
    'printf x | tee /dev/null', 'git commit -m "committee notes"')
  $i = 0
  foreach ($cmd in $bashEdits) {
    $i++
    Check "bash-edit-$i [$cmd]" '{"steps":1,"stepsBeforeFirstEdit":0,"minutesToFirstEdit":0,"minutes":0}' @(
      (Write-Transcript "bash-edit-$i.jsonl" @(, @($ts, 'Bash', @{ command = $cmd }))))
  }
  $i = 0
  foreach ($cmd in $bashReads) {
    $i++
    Check "bash-read-$i [$cmd]" '{"steps":1,"minutes":0}' @(
      (Write-Transcript "bash-read-$i.jsonl" @(, @($ts, 'Bash', @{ command = $cmd }))))
  }
  Check 'edit-after-bash-read' '{"steps":3,"stepsBeforeFirstEdit":1,"minutesToFirstEdit":0.5,"minutes":1.5}' @(
    (Write-Transcript 'edit-after-bash-read.jsonl' @(
      @('2026-09-23T10:00:00Z', 'Bash', @{ command = 'ls > /dev/null' }),
      @('2026-09-23T10:00:30Z', 'Edit', @{ file_path = '/repo/a.sh' }),
      @('2026-09-23T10:01:30Z', 'Bash', @{ command = "sed -i '' 's/a/b/' /repo/a.sh" }))))

  Check 'missing-file' '__FAIL__' @((Join-Path $tmp 'nope.jsonl'))
  Check 'directory' '__FAIL__' @($tmp)
  Check 'usage' '__FAIL__' @() -wantRc 2

  if ($Leg -eq 'sh') {
    $noJq = Join-Path $tmp 'nojq'
    New-Item -ItemType Directory -Path $noJq -Force | Out-Null
    Check 'jq-absent' '__FAIL__' @((Join-Path $fx 'dispatch-sample.jsonl')) @{ PATH = $noJq }
  }
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "measure-dispatch ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
