#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for check-size-budgets.ps1 (issue #295).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/check-size-budgets'
$fix = 'tests/fixtures/check-size-budgets'
$gold = Join-Path $root "$fix/_expected"
$u8 = [System.Text.UTF8Encoding]::new($false)

# The edited-copy cases rewrite one table row of the leg's own script; the
# governed table has the same row shape in both legs.
function Read-Src { return [System.IO.File]::ReadAllText("$script.$Leg", $u8) }
function New-CopyBase([string]$tag) { return (Join-Path ([System.IO.Path]::GetTempPath()) ("csb_${tag}_" + [System.Guid]::NewGuid().ToString('N'))) }
function Invoke-Copy([string]$base, [string]$text, [string]$arg) {
  [System.IO.File]::WriteAllText("$base.$Leg", $text, $u8)
  $r = Invoke-Leg -Script $base -Args @($arg)
  Remove-Item "$base.$Leg" -Force -ErrorAction SilentlyContinue
  return $r
}

$cases = @(
  'at-ceiling|0',
  'one-over|1',
  'line-flat-byte-over|1',
  'byte-flat-word-over|1',
  'missing-file|1',
  'missing-closure-member|1'
)

$pass = 0; $fail = 0
Push-Location $root
try {
  foreach ($spec in $cases) {
    $parts = $spec -split '\|'
    $name = $parts[0]; $wantExit = [int]$parts[1]
    $exp = Join-Path $gold "$name.txt"
    if (-not (Test-Path $exp)) { Write-Host "FAIL ${name}: missing golden $exp"; $fail++; continue }
    $r = Invoke-Leg -Script $script -Args @("$fix/$name")
    $rc = $r.rc
    $got = $r.out + $r.err
    $gotN = ($got -replace "`r`n", "`n").TrimEnd("`n")
    $want = ([System.IO.File]::ReadAllText($exp, [System.Text.UTF8Encoding]::new($false)) -replace "`r`n", "`n").TrimEnd("`n")
    if ($gotN -eq $want -and $rc -eq $wantExit) { $pass++ }
    else {
      $fail++
      Write-Host "FAIL $name`: rc=$rc (want $wantExit)"
      Write-Host "--- want ---"; Write-Host $want
      Write-Host "--- got ----"; Write-Host $gotN
    }
  }

  # --- parity-guard: the length-parity refusal (issue #399) ----------------
  $guardGold = Join-Path $gold 'parity-guard.stderr.txt'
  if (-not (Test-Path $guardGold)) { Write-Host "FAIL parity-guard: missing golden $guardGold"; $fail++ }
  else {
    $src = Read-Src
    $rowRx = [regex]'(?m)^((?:skills|agents)/\S+[ \t]+)\d+(?=[ \t]+\d+[ \t]+\d+[ \t]*\r?$)'
    $desynced = $rowRx.Replace($src, '${1}-', 1)
    $gr = Invoke-Copy (New-CopyBase 'guard') $desynced "$fix/at-ceiling"
    $grc = $gr.rc
    $guardOut = $gr.out
    $guardErr = ($gr.err -replace "`r`n", "`n").TrimEnd("`n")
    $guardWant = ([System.IO.File]::ReadAllText($guardGold, [System.Text.UTF8Encoding]::new($false)) -replace "`r`n", "`n").TrimEnd("`n")
    if ($guardOut -eq '' -and $grc -eq 1 -and $guardErr -eq $guardWant) { $pass++ }
    else {
      $fail++
      Write-Host "FAIL parity-guard: rc=$grc (want 1), stdout=[$guardOut] (want empty)"
      Write-Host "--- want err ---"; Write-Host $guardWant
      Write-Host "--- got err ----"; Write-Host $guardErr
    }
  }

  # --- positional-desync: a moved row carries its own ceilings (#428) -------
  $swapGold = Join-Path $gold 'at-ceiling.txt'
  if (-not (Test-Path $swapGold)) { Write-Host "FAIL positional-desync: missing golden $swapGold"; $fail++ }
  else {
    $lines = (Read-Src) -split "`n"
    $ia = -1; $ib = -1
    for ($j = 0; $j -lt $lines.Count; $j++) {
      $first = ($lines[$j].Trim() -split '\s+')[0]
      if ($first -eq 'agents/design-reviewer.md') { $ia = $j }
      if ($first -eq 'agents/implementer.md') { $ib = $j }
    }
    if ($ia -ge 0 -and $ib -ge 0) { $tmpRow = $lines[$ia]; $lines[$ia] = $lines[$ib]; $lines[$ib] = $tmpRow }
    $sr = Invoke-Copy (New-CopyBase 'swap') ($lines -join "`n") "$fix/at-ceiling"
    $swapRc = $sr.rc
    $swapRaw = $sr.out + $sr.err
    $swapOut = ($swapRaw -replace "`r`n", "`n").TrimEnd("`n")
    $swapWant = ([System.IO.File]::ReadAllText($swapGold, [System.Text.UTF8Encoding]::new($false)) -replace "`r`n", "`n").TrimEnd("`n")
    $sortedGot = (($swapOut -split "`n") | Sort-Object) -join "`n"
    $sortedWant = (($swapWant -split "`n") | Sort-Object) -join "`n"
    if ($swapRc -eq 0 -and $swapOut -ne $swapWant -and $sortedGot -eq $sortedWant) { $pass++ }
    else {
      $fail++
      Write-Host "FAIL positional-desync: rc=$swapRc (want 0), the two swapped rows must reorder the stream, not reattribute ceilings"
      if ($swapOut -eq $swapWant) { Write-Host "  the row swap was a no-op, re-key it to the current table shape" }
      Write-Host "--- want (sorted) ---"; Write-Host $sortedWant
      Write-Host "--- got  (sorted) ---"; Write-Host $sortedGot
    }
  }

  # --- malformed-row parity: the other three single-row edits (#428) --------
  $malRefusal = (([System.IO.File]::ReadAllText((Join-Path $gold 'parity-guard.stderr.txt'), $u8) -replace "`r`n", "`n").TrimEnd("`n")).Replace(
    'CEILINGS(38), BYTE_CEILINGS(39) and WORD_CEILINGS(39)', 'CEILINGS(39), BYTE_CEILINGS(39) and WORD_CEILINGS(38)')
  $wideStream = ((([System.IO.File]::ReadAllText((Join-Path $gold 'at-ceiling.txt'), $u8) -replace "`r`n", "`n").TrimEnd("`n")) -split "`n" | ForEach-Object {
    if ($_.Contains('skills/setup/SKILL.md')) { ($_.Replace('/28000', '/99999999999')).Replace('/4000', '/99999999999') } else { $_ }
  }) -join "`n"
  $malCases = @(
    @{ name = 'short'; rep = '${1}';                          rc = 1; out = '';          err = $malRefusal
       rx = '(?m)^((?:skills|agents)/\S+[ \t]+\d+[ \t]+\d+)[ \t]+\d+[ \t]*\r?$' },
    @{ name = 'long';  rep = '${1} 999';                      rc = 1; out = '';          err = $malRefusal
       rx = '(?m)^((?:skills|agents)/\S+[ \t]+\d+[ \t]+\d+[ \t]+\d+)[ \t]*\r?$' },
    @{ name = 'wide';  rep = '${1}99999999999 99999999999';   rc = 0; out = $wideStream; err = ''
       rx = '(?m)^((?:skills|agents)/\S+[ \t]+\d+[ \t]+)\d+[ \t]+\d+(?=[ \t]*\r?$)' }
  )
  foreach ($mal in $malCases) {
    $edited = ([regex]$mal.rx).Replace((Read-Src), $mal.rep, 1)
    $mr = Invoke-Copy (New-CopyBase 'mal') $edited "$fix/at-ceiling"
    $mrc = $mr.rc
    $malOut = ($mr.out -replace "`r`n", "`n").TrimEnd("`n")
    $malErr = ($mr.err -replace "`r`n", "`n").TrimEnd("`n")
    if ($mrc -eq $mal.rc -and $malOut -eq $mal.out -and $malErr -eq $mal.err) { $pass++ }
    else {
      $fail++
      Write-Host "FAIL malformed-row/$($mal.name): rc=$mrc (want $($mal.rc))"
      Write-Host "--- want out ---"; Write-Host $mal.out
      Write-Host "--- got  out ---"; Write-Host $malOut
      Write-Host "--- want err ---"; Write-Host $mal.err
      Write-Host "--- got  err ---"; Write-Host $malErr
    }
  }

  # --- empty-closure-table: no closures is a no-op, not an error (#491) -----
  $atGold = ([System.IO.File]::ReadAllText((Join-Path $gold 'at-ceiling.txt'), $u8) -replace "`r`n", "`n").TrimEnd("`n")
  $isClosure = { param($l) $l.StartsWith("CLOSURE`t", [System.StringComparison]::Ordinal) }
  $emptyWant = ((($atGold -split "`n") | Where-Object { -not (& $isClosure $_) }) -join "`n")
  $emptyRx = if ($Leg -eq 'ps1') { [regex]'(?s)(\$closureTable = @''\r?\n).*?(\r?\n''@)' }
             else { [regex]"(?s)(done <<'CLOSURE_TABLE'\r?\n).*?(CLOSURE_TABLE\r?\n)" }
  $emptied = $emptyRx.Replace((Read-Src), '${1}${2}', 1)
  $er = Invoke-Copy (New-CopyBase 'empty') $emptied "$fix/at-ceiling"
  $erc = $er.rc
  $emptyOut = ($er.out -replace "`r`n", "`n").TrimEnd("`n")
  $emptyErr = ($er.err -replace "`r`n", "`n").TrimEnd("`n")
  if ($erc -eq 0 -and $emptyOut -eq $emptyWant -and $emptyErr -eq '') { $pass++ }
  else {
    $fail++
    Write-Host "FAIL empty-closure-table: rc=$erc (want 0), stderr=[$emptyErr] (want empty)"
    Write-Host "--- want ---"; Write-Host $emptyWant
    Write-Host "--- got  ---"; Write-Host $emptyOut
  }

  # --- excluded-untouched: the six branch-gated files are outside every
  $excTree = Join-Path ([System.IO.Path]::GetTempPath()) ("csb_exc_" + [System.Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $excTree -Force | Out-Null
  Copy-Item -Path (Join-Path $root "$fix/at-ceiling/*") -Destination $excTree -Recurse -Force
  foreach ($x in @('skills/solve-milestone/parallel-waves.md',
                   'skills/solve-milestone/milestone-granularity.md',
                   'skills/solve-milestone/trello-sync.md',
                   'skills/solve-issue/async-mode.md',
                   'skills/solve-issue/md-epic-fanout.md',
                   'skills/triage/blocker-resolver-dispatch.md')) {
    [System.IO.File]::AppendAllText((Join-Path $excTree $x), "excluded branch gated padding words`n", $u8)
  }
  $xr = Invoke-Leg -Script $script -Args @($excTree)
  $excRaw = $xr.out + $xr.err
  Remove-Item $excTree -Recurse -Force
  $excOut = ($excRaw -replace "`r`n", "`n").TrimEnd("`n")
  $excGotCl = ((($excOut -split "`n") | Where-Object { & $isClosure $_ }) -join "`n")
  $excWantCl = ((($atGold -split "`n") | Where-Object { & $isClosure $_ }) -join "`n")
  $excGotRest = ((($excOut -split "`n") | Where-Object { -not (& $isClosure $_) }) -join "`n")
  if ($excWantCl -ne '' -and $excGotCl -eq $excWantCl -and $excGotRest -ne $emptyWant) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL excluded-untouched: editing a branch-gated file must leave every CLOSURE line unchanged"
    if ($excGotRest -eq $emptyWant) { Write-Host "  the perturbation was a no-op, re-key it to the current fixture tree" }
    Write-Host "--- want closure ---"; Write-Host $excWantCl
    Write-Host "--- got  closure ---"; Write-Host $excGotCl
  }
} finally { Pop-Location }
Write-Host "check-size-budgets ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
