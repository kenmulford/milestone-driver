#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for check-packet.ps1 (issue #722).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/check-packet'
$fix = Join-Path $root 'tests/fixtures/check-packet'
$utf8 = [System.Text.UTF8Encoding]::new($false)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }

$pass = 0; $fail = 0
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ckp_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

function Ok([string]$name, [bool]$cond, [string]$detail) {
  if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name $detail" }
}
function Show([string]$s) { return (($s -replace "`t", '\t') -replace "`n", '\n') }

try {
  # A committed worktree holding the fixture source, so Base: has a real HEAD to match.
  $wt = Join-Path $tmp 'wt'
  New-Item -ItemType Directory -Path (Join-Path $wt 'src') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $fix 'src/app.md') -Destination (Join-Path $wt 'src/app.md')
  & git -C $wt init -q 2>$null | Out-Null
  & git -C $wt config core.hooksPath (Join-Path $wt '.git/no-such-hooks') 2>$null | Out-Null
  & git -C $wt config commit.gpgsign false 2>$null | Out-Null
  & git -C $wt config user.email 'tests@milestone-driver.invalid' 2>$null | Out-Null
  & git -C $wt config user.name 'check-packet tests' 2>$null | Out-Null
  & git -C $wt add -A 2>$null | Out-Null
  & git -C $wt commit -q -m base 2>$null | Out-Null
  $head = (& git -C $wt rev-parse HEAD 2>$null | Out-String).Trim()
  if ($head -notmatch '^[0-9a-f]{40}$') { Write-Error "FATAL: fixture repo has no HEAD: [$head]"; exit 3 }

  $clean = [System.IO.File]::ReadAllText((Join-Path $fix 'clean.md'), $utf8)
  $stale = '0000000000000000000000000000000000000000'
  # Built from parts so scripts/check-citations.sh does not read these packet
  # headings as this file's own citations.
  $src = 'src/app.md'; $miss = 'no such anchor'
  $cases = @(
    @{ name = 'clean'; body = $clean; extra = @(); rc = 0; out = "SUMMARY`tok=16`tfailed=0`n" },
    @{ name = 'clean-light'; body = $clean; extra = @('light'); rc = 0; out = "SUMMARY`tok=15`tfailed=0`n" },
    @{ name = 'worktree-trailing-slash'; body = $clean.Replace('__WORKTREE__', "$wt/"); extra = @(); rc = 0; out = "SUMMARY`tok=16`tfailed=0`n" },
    @{ name = 'stale-base'; body = $clean.Replace('__BASE__', $stale); extra = @(); rc = 1
      out = "FAIL`tbase`tBase: $stale != HEAD $head`nSUMMARY`tok=15`tfailed=1`n" },
    @{ name = 'wrong-worktree'; body = $clean.Replace('__WORKTREE__', '/nowhere/else'); extra = @(); rc = 1
      out = "FAIL`tworktree`tWorktree: /nowhere/else != $wt`nSUMMARY`tok=15`tfailed=1`n" },
    @{ name = 'no-issue-line'; body = $clean.Replace("Issue: #1`n", ''); extra = @(); rc = 1
      out = "FAIL`theader`tmissing Issue: line`nSUMMARY`tok=15`tfailed=1`n" },
    @{ name = 'no-tests'; body = $clean.Replace("`n## Tests`n", "`n"); extra = @(); rc = 1
      out = "FAIL`tsection`tmissing ## Tests`nSUMMARY`tok=15`tfailed=1`n" },
    @{ name = 'no-tests-light'; body = $clean.Replace("`n## Tests`n", "`n"); extra = @('light'); rc = 0; out = "SUMMARY`tok=15`tfailed=0`n" },
    @{ name = 'rules-only-fenced'; body = $clean.Replace("`n## Rules`n`nnone`n", "`n"); extra = @(); rc = 1
      out = "FAIL`tsection`tmissing ## Rules`nSUMMARY`tok=15`tfailed=1`n" },
    @{ name = 'unresolvable-anchor'; body = $clean.Replace("### $src (beta helper line)", "### $src ($miss)"); extra = @(); rc = 1
      out = "FAIL`tcitation`t$src ($miss): resolve-citation: anchor not found: '$miss' in $wt/$src`nSUMMARY`tok=15`tfailed=1`n" }
  )

  $packets = @{}
  foreach ($c in $cases) {
    $p = Join-Path $tmp "$($c.name).md"
    [System.IO.File]::WriteAllText($p, $c.body.Replace('__BASE__', $head).Replace('__WORKTREE__', $wt), $utf8)
    $packets[$c.name] = $p
    $r = Invoke-Leg -Script $script -Args (@($p, $wt) + $c.extra)
    Ok $c.name ($r.rc -eq $c.rc -and $r.out -ceq $c.out -and $r.err -ceq '') "rc=$($r.rc) (want $($c.rc))`n  out got  [$(Show $r.out)]`n  out want [$(Show $c.out)]`n  err [$(Show $r.err)]"
  }

  foreach ($u in @(
      @{ name = 'usage-no-args'; args = @() },
      @{ name = 'usage-bad-profile'; args = @($packets['clean'], $wt, 'heavy') },
      @{ name = 'unreadable-packet'; args = @((Join-Path $tmp 'nope.md'), $wt) },
      @{ name = 'worktree-not-a-dir'; args = @($packets['clean'], (Join-Path $tmp 'nope')) })) {
    $r = Invoke-Leg -Script $script -Args $u.args
    Ok $u.name ($r.rc -eq 2 -and $r.out -ceq '' -and $r.err -like '*check-packet*') "rc=$($r.rc) out=[$(Show $r.out)] err=[$(Show $r.err)]"
  }

  # Parity needs both interpreters; the sh leg is the one that guarantees bash.
  if ($Leg -eq 'sh') {
    foreach ($c in $cases) {
      $got = @{}
      foreach ($l in @('sh', 'ps1')) {
        Set-Leg $l
        $got[$l] = (Invoke-Leg -Script $script -Args (@($packets[$c.name], $wt) + $c.extra)).out
      }
      Set-Leg $Leg
      Ok "legs-byte-identical-$($c.name)" ($got['sh'] -ne '' -and $got['sh'] -ceq $got['ps1']) "sh=[$(Show $got['sh'])] ps1=[$(Show $got['ps1'])]"
    }
  }
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "check-packet ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
