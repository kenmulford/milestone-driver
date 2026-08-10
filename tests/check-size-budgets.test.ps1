#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for check-size-budgets.ps1 (issue #295).
# Asserts the pwsh checker against the SAME
# tests/fixtures/check-size-budgets/_expected/*.txt golden files the .sh
# runner uses — cross-impl parity. See that runner's header for what each
# case proves.
#
# Fixture-prose caveat: line-flat-byte-over and byte-flat-word-over are both
# BYTE-FOR-BYTE-SIZED COPIES of the at-ceiling tree, each with one surgical
# edit. Their inherited prose therefore describes the at-ceiling copy, not
# itself: line-flat-byte-over's file says it "stands at exactly 4500 bytes",
# that "both report 4500 here", and that its padding line is "sized so this
# fixture lands on exactly 4500 bytes", while the file it sits in is 4606 bytes
# and is the deliberately-over case; it also names line-flat-byte-over/ as the
# sibling from inside line-flat-byte-over/. The at-ceiling original in turn
# says "only this file's line count and byte count are asserted", which the
# word axis made stale. Do not "fix" any of that prose. The
# byte-for-byte-sized-copy property is what these cases rest on, and rewording
# a byte-pinned fixture moves its totals and forces a golden regeneration for
# no test value.
#
# parity-guard, positional-desync and the three malformed-row cases have no
# fixture tree: the governed set is a table in the checker's OWN source, so no
# fixture can reach it. Each of those cases builds an edited COPY of the
# checker instead (garble a column, swap two rows, drop a column, add a surplus
# column, widen a ceiling past int32 max) and asserts what the copy does. See
# the three blocks below the loop.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $root 'scripts/check-size-budgets.ps1'
$fix = 'tests/fixtures/check-size-budgets'
$gold = Join-Path $root "$fix/_expected"
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }

# name|wantExit
$cases = @(
  'at-ceiling|0',
  'one-over|1',
  'line-flat-byte-over|1',
  'byte-flat-word-over|1',
  'missing-file|1'
)

$pass = 0; $fail = 0
# Run from the repo root so any path text in the output is checkout-independent
# (matches golden). Mirrors tests/ci-preflight-steps.test.ps1.
Push-Location $root
try {
  foreach ($spec in $cases) {
    $parts = $spec -split '\|'
    $name = $parts[0]; $wantExit = [int]$parts[1]
    $exp = Join-Path $gold "$name.txt"
    if (-not (Test-Path $exp)) { Write-Host "FAIL ${name}: missing golden $exp"; $fail++; continue }
    # Capture stdout AND stderr to temp files and read them back as UTF-8 bytes
    # so a multibyte char survives byte-exact, mirroring the ci-preflight-steps
    # runner. stderr is appended to stdout to mirror the .sh runner's `2>&1`,
    # so a case that starts emitting on stderr fails on BOTH twins instead of
    # only the bash one. Every fixture case here writes nothing to stderr, so
    # the concatenation order is unobservable and these four comparisons are
    # unchanged; the parity-guard case below reads the two streams separately,
    # because it has to assert stdout is empty.
    $tmp = New-TemporaryFile
    $tmpErr = New-TemporaryFile
    $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $script, "$fix/$name") -NoNewWindow -Wait -RedirectStandardOutput $tmp.FullName -RedirectStandardError $tmpErr.FullName -PassThru
    $rc = $p.ExitCode
    $gotOut = [System.IO.File]::ReadAllText($tmp.FullName, [System.Text.UTF8Encoding]::new($false))
    $gotErr = [System.IO.File]::ReadAllText($tmpErr.FullName, [System.Text.UTF8Encoding]::new($false))
    $got = $gotOut + $gotErr
    Remove-Item $tmp.FullName, $tmpErr.FullName -Force
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
  # Same case the .sh runner runs, against the same golden: garble ONE column
  # in a COPY of the checker (blank the first governed row's LINE ceiling to
  # "-", leaving 15/14/15/15) and assert all three halves of the refusal, EMPTY
  # stdout, exit 1, and the exact stderr line. No fixture tree can reach this
  # path, because a fixture is input and the table is the script's own source.
  # If a table rewrite ever makes the edit a no-op the case still fails loud:
  # the unmodified copy prints its OK records and stdout is then not empty.
  $guardGold = Join-Path $gold 'parity-guard.stderr.txt'
  if (-not (Test-Path $guardGold)) { Write-Host "FAIL parity-guard: missing golden $guardGold"; $fail++ }
  else {
    $src = [System.IO.File]::ReadAllText($script, [System.Text.UTF8Encoding]::new($false))
    # Table rows are the only lines starting at column 0 with skills/ or
    # agents/ and carrying three numeric columns — mirrors the .sh runner's awk.
    # The trailing `\r?` is load-bearing: .NET multiline `$` matches before the
    # `\n`, so on a CRLF checkout (Windows core.autocrlf) a bare `[ \t]*$`
    # never matches a table row and the surgery silently becomes a no-op.
    $rowRx = [regex]'(?m)^((?:skills|agents)/\S+[ \t]+)\d+(?=[ \t]+\d+[ \t]+\d+[ \t]*\r?$)'
    $desynced = $rowRx.Replace($src, '${1}-', 1)
    $guardScript = Join-Path ([System.IO.Path]::GetTempPath()) ("csb_guard_" + [System.Guid]::NewGuid().ToString('N') + ".ps1")
    # UTF-8 no BOM, and a .ps1 name: pwsh -File rejects any other extension.
    [System.IO.File]::WriteAllText($guardScript, $desynced, [System.Text.UTF8Encoding]::new($false))
    $gOut = New-TemporaryFile
    $gErr = New-TemporaryFile
    $gp = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $guardScript, "$fix/at-ceiling") -NoNewWindow -Wait -RedirectStandardOutput $gOut.FullName -RedirectStandardError $gErr.FullName -PassThru
    $grc = $gp.ExitCode
    $guardOut = [System.IO.File]::ReadAllText($gOut.FullName, [System.Text.UTF8Encoding]::new($false))
    $guardErr = ([System.IO.File]::ReadAllText($gErr.FullName, [System.Text.UTF8Encoding]::new($false)) -replace "`r`n", "`n").TrimEnd("`n")
    Remove-Item $gOut.FullName, $gErr.FullName, $guardScript -Force
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
  # Same case the .sh runner runs. Before #428 the governed set was
  # free-standing parallel arrays, so swapping agents/design-reviewer.md and
  # agents/triage-reviewer.md inside $files ALONE kept every length equal,
  # sailed past the parity guard, measured each file against the other's
  # ceilings and still exited 0. One row per file removes that edit: the
  # smallest unit of the table that names a file carries all of its ceilings.
  # Swap two ROWS in a COPY of the checker and the stream must be the same
  # records in a different ORDER, never the same order with reattributed
  # ceilings:
  #   sorted == at-ceiling golden  the two rows carry DIFFERENT ceilings, so a
  #                                reattribution changes a record's text and
  #                                survives the sort; a reorder does not
  #   raw    != at-ceiling golden  the swap actually landed. Without this half
  #                                a table rewrite that made the surgery a
  #                                no-op would pass vacuously, the same
  #                                fail-loud property parity-guard relies on.
  # THE PAIR MUST DIFFER ON AT LEAST ONE CEILING, or the sorted half asserts
  # nothing: two rows carrying identical ceilings produce identical record text,
  # so a reattribution would be invisible to it. #428's own pair was
  # design-reviewer/triage-reviewer, and it still satisfies that. #464 collapsed
  # their LINE column to 120/120 but left them apart on BYTES (16500 vs 17000),
  # and the mutation is still caught there. Re-keying the swap to
  # design-reviewer (120/16500/2700) against implementer.md (130/15000/2300) is
  # HARDENING, not a repair: that pair differs on ALL THREE axes, so it survives
  # a future ratchet that collapses any two of them. Re-key again only if a pair
  # goes identical on every axis.
  $swapGold = Join-Path $gold 'at-ceiling.txt'
  if (-not (Test-Path $swapGold)) { Write-Host "FAIL positional-desync: missing golden $swapGold"; $fail++ }
  else {
    $lines = [System.IO.File]::ReadAllText($script, [System.Text.UTF8Encoding]::new($false)) -split "`n"
    $ia = -1; $ib = -1
    for ($j = 0; $j -lt $lines.Count; $j++) {
      $first = ($lines[$j].Trim() -split '\s+')[0]
      if ($first -eq 'agents/design-reviewer.md') { $ia = $j }
      if ($first -eq 'agents/implementer.md') { $ib = $j }
    }
    if ($ia -ge 0 -and $ib -ge 0) { $tmpRow = $lines[$ia]; $lines[$ia] = $lines[$ib]; $lines[$ib] = $tmpRow }
    $swapScript = Join-Path ([System.IO.Path]::GetTempPath()) ("csb_swap_" + [System.Guid]::NewGuid().ToString('N') + ".ps1")
    [System.IO.File]::WriteAllText($swapScript, ($lines -join "`n"), [System.Text.UTF8Encoding]::new($false))
    $sOut = New-TemporaryFile
    $sErr = New-TemporaryFile
    $sp = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $swapScript, "$fix/at-ceiling") -NoNewWindow -Wait -RedirectStandardOutput $sOut.FullName -RedirectStandardError $sErr.FullName -PassThru
    $swapRc = $sp.ExitCode
    $swapRaw = [System.IO.File]::ReadAllText($sOut.FullName, [System.Text.UTF8Encoding]::new($false)) +
               [System.IO.File]::ReadAllText($sErr.FullName, [System.Text.UTF8Encoding]::new($false))
    Remove-Item $sOut.FullName, $sErr.FullName, $swapScript -Force
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
  # Same three cases the .sh runner runs, against the same two goldens.
  # parity-guard above garbles a LINE ceiling and leaves 15/14/15/15. Three
  # further single-row edits are the ones where the two twins' PARSES can
  # disagree:
  #   short   word column deleted                 -> refusal, counts 15/15/15/14
  #   long    surplus fifth column                -> refusal, counts 15/15/15/14
  #   wide    byte AND word ceilings past int32   -> clean OK record, exit 0
  # The .sh twin's `read -r f line_ceiling byte_ceiling word_ceiling` fills
  # columns 2 and 3 whatever the row's width and folds every surplus column
  # into column 4, so short and long both KEEP their line and byte ceilings and
  # lose only the word one. The checker's $c1/$c2/$c3 fold exists to match
  # that; gating every ceiling add on an exact 4-column row instead dropped the
  # earlier ceilings too and printed 15/14/14/14 for these same two tables, so
  # the two twins' refusals were not byte-identical. `wide` is the other half:
  # the digit check accepts any number of digits and the .sh twin's arithmetic
  # is 64-bit, so 99999999999 is simply a very loose ceiling there, while
  # casting to [int] here threw under $ErrorActionPreference = 'Stop' and
  # exited 1 with empty stdout. It widens the byte AND word columns in one row,
  # so BOTH [long] lists stay covered by the one case.
  #
  # Both expectations are DERIVED from a committed golden by rewriting only the
  # numbers the surgery moves, so a reworded refusal or a retuned ceiling still
  # has exactly one place to update and the two twins cannot drift apart. A
  # surgery that no-ops fails loud, same as the two cases above: the unmodified
  # copy's stream matches neither expectation.
  $u8 = [System.Text.UTF8Encoding]::new($false)
  $malRefusal = (([System.IO.File]::ReadAllText((Join-Path $gold 'parity-guard.stderr.txt'), $u8) -replace "`r`n", "`n").TrimEnd("`n")).Replace(
    'CEILINGS(14), BYTE_CEILINGS(15) and WORD_CEILINGS(15)', 'CEILINGS(15), BYTE_CEILINGS(15) and WORD_CEILINGS(14)')
  $wideStream = ((([System.IO.File]::ReadAllText((Join-Path $gold 'at-ceiling.txt'), $u8) -replace "`r`n", "`n").TrimEnd("`n")).Replace(
    '/30000', '/99999999999')).Replace('/4300', '/99999999999')
  $malCases = @(
    @{ name = 'short'; rep = '${1}';                          rc = 1; out = '';          err = $malRefusal
       rx = '(?m)^((?:skills|agents)/\S+[ \t]+\d+[ \t]+\d+)[ \t]+\d+[ \t]*\r?$' },
    @{ name = 'long';  rep = '${1} 999';                      rc = 1; out = '';          err = $malRefusal
       rx = '(?m)^((?:skills|agents)/\S+[ \t]+\d+[ \t]+\d+[ \t]+\d+)[ \t]*\r?$' },
    @{ name = 'wide';  rep = '${1}99999999999 99999999999';   rc = 0; out = $wideStream; err = ''
       rx = '(?m)^((?:skills|agents)/\S+[ \t]+\d+[ \t]+)\d+[ \t]+\d+(?=[ \t]*\r?$)' }
  )
  foreach ($mal in $malCases) {
    $malSrc = [System.IO.File]::ReadAllText($script, $u8)
    $edited = ([regex]$mal.rx).Replace($malSrc, $mal.rep, 1)
    $malScript = Join-Path ([System.IO.Path]::GetTempPath()) ("csb_mal_" + [System.Guid]::NewGuid().ToString('N') + ".ps1")
    [System.IO.File]::WriteAllText($malScript, $edited, $u8)
    $mOut = New-TemporaryFile
    $mErr = New-TemporaryFile
    $mp = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $malScript, "$fix/at-ceiling") -NoNewWindow -Wait -RedirectStandardOutput $mOut.FullName -RedirectStandardError $mErr.FullName -PassThru
    $mrc = $mp.ExitCode
    $malOut = ([System.IO.File]::ReadAllText($mOut.FullName, $u8) -replace "`r`n", "`n").TrimEnd("`n")
    $malErr = ([System.IO.File]::ReadAllText($mErr.FullName, $u8) -replace "`r`n", "`n").TrimEnd("`n")
    Remove-Item $mOut.FullName, $mErr.FullName, $malScript -Force
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
} finally { Pop-Location }
Write-Host "check-size-budgets.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
