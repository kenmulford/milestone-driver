#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for triage-cache.ps1 (issue #441).
# Twin of triage-cache.test.sh: drives the SAME triage-cache.cases.tsv table
# against the SAME fixtures/triage-cache/_expected/* goldens, so the bash and
# pwsh legs stay byte-identical. See that runner's header for what each column
# means and what each case proves.
#
# RAW vs NORMALIZED — same rule as tests/resolve-citation.test.ps1 (RAW vs NORMALIZED — the distinction):
#   * The ACTUAL stdout/stderr is captured RAW, via ProcessStartInfo +
#     StreamReader.ReadToEnd, which performs NO newline translation. Joining
#     PowerShell's line-split array (or piping through `>`) normalizes line
#     endings, and a runner that does so cannot observe CRLF creep AT ALL — on
#     the very leg that runs on Windows, where CRLF creep is the natural failure
#     mode.
#   * The GOLDEN gets ONE normalization, CRLF -> LF, for a CRLF checkout.
# ProcessStartInfo also gives EXACT argument passing (ArgumentList, no shell
# quoting) and an explicit WorkingDirectory, so relative fixture paths resolve
# the way the bash leg's subshell cd resolves them.
#
# The `write` subcommand MUTATES its root, so it cannot be driven from a
# committed fixture; it is covered by the bespoke blocks below the loop against
# fresh temp workspaces. The cache FILE is asserted by PARSED CONTENT, not
# bytes: the two twins use different JSON serializers, and only stdout/stderr is
# byte-pinned. The final bespoke block is pwsh-only, and is the positive form of
# the bash leg's jq-absent case: with PATH emptied this leg still answers
# correctly, because it consults no external tool.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Script = Join-Path $Root 'scripts' 'triage-cache.ps1'
$Cases = Join-Path $Here 'triage-cache.cases.tsv'
$Fix = Join-Path $Here 'fixtures' 'triage-cache'
$Gold = Join-Path $Fix '_expected'
$ScriptName = 'triage-cache.ps1'
$RepoGitignore = Join-Path $Root '.milestone-config' '.gitignore'
if (-not (Test-Path $Script)) { Write-Error "FATAL: missing $Script"; exit 3 }
if (-not (Test-Path $Cases)) { Write-Error "FATAL: missing $Cases"; exit 3 }
if (-not (Test-Path $Fix)) { Write-Error "FATAL: missing $Fix"; exit 3 }
$Script = (Resolve-Path $Script).Path
$Fix = (Resolve-Path $Fix).Path
$pwshBin = (Get-Command pwsh).Source

$utf8 = [System.Text.UTF8Encoding]::new($false)
$TAB = "`t"
$pass = 0; $fail = 0
$ExpectCols = 5
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

# Eq-Exact — BYTE-EXACT comparison. PowerShell's `-eq` on strings is
# case-INSENSITIVE and culture-sensitive, so it is not the assertion this
# runner's contract requires; StringComparison.Ordinal is
# (tests/resolve-citation.test.ps1 (function Eq-Exact) makes the same call, with the
# measurements behind it).
function Eq-Exact([string]$a, [string]$b) {
  return [string]::Equals($a, $b, [System.StringComparison]::Ordinal)
}

function Show-Escaped([string]$s) {
  if ($null -eq $s) { return '' }
  return ((($s -replace "`r", '\r') -replace "`n", '\n') -replace "`t", '\t')
}

# Read-Golden — a NAMED-BUT-MISSING golden is FATAL. Returning '' here would
# silently turn such a case into "expect empty", i.e. a green run asserting
# nothing.
function Read-Golden([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Error "FATAL: names a missing golden: $path"
    exit 3
  }
  return ([System.IO.File]::ReadAllText($path, $utf8) -replace "`r`n", "`n")
}

function Ok { $script:pass++ }
function No([string]$msg) { $script:fail++; Write-Host "FAIL $msg" }

# Invoke-Tc — run the script under test with exact arguments and an explicit
# working directory, returning RAW stdout/stderr plus the exit code. Both
# streams are read asynchronously BEFORE WaitForExit so a full pipe buffer
# cannot deadlock the child. $envPath, when given, REPLACES PATH in the child.
function Invoke-Tc([string[]]$scriptArgs, [string]$workDir, [string]$envPath = $null) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $pwshBin
  foreach ($a in @('-NoProfile', '-File', $Script)) { [void]$psi.ArgumentList.Add($a) }
  foreach ($a in $scriptArgs) { [void]$psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $workDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  if ($null -ne $envPath) { $psi.Environment['PATH'] = $envPath }
  $p = [System.Diagnostics.Process]::Start($psi)
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{
    out = $outTask.GetAwaiter().GetResult()
    err = $errTask.GetAwaiter().GetResult()
    rc  = $p.ExitCode
  }
}

$caseCount = 0
foreach ($rawRow in Get-Content -LiteralPath $Cases) {
  # Strip the CRLF checkout's CR FIRST, then apply the SAME blank/comment skip
  # the bash leg applies: empty row, or '#' at COLUMN 0.
  $row = $rawRow -replace "`r$", ''
  if ($row -eq '' -or $row.StartsWith('#')) { continue }
  $cols = $row -split "`t"
  if ($cols.Count -ne $ExpectCols) {
    Write-Error "FATAL: row failed to parse (got $($cols.Count) fields, want $ExpectCols): [$row]"
    exit 1
  }
  $caseCount++
  $name = $cols[0]; $argsCell = $cols[1]; $stdoutFile = $cols[2]
  $wantExit = [int]$cols[3]; $stderrFile = $cols[4]

  $expOut = if ($stdoutFile -ne '') { Read-Golden (Join-Path $Gold $stdoutFile) } else { '' }
  $expErr = ''
  if ($stderrFile -ne '') {
    $expErr = (Read-Golden (Join-Path $Gold $stderrFile)) -replace '__SCRIPT__', $ScriptName
  }

  # -split ' ' rather than the regex default: the column is a plain word list,
  # and no cell holds a glob or an embedded space (see the table header).
  $runArgs = @($argsCell -split ' ')
  $r = Invoke-Tc $runArgs $Fix

  if ($r.rc -eq $wantExit -and (Eq-Exact $r.out $expOut) -and (Eq-Exact $r.err $expErr)) { Ok }
  else {
    No "${name}: rc=$($r.rc) (want $wantExit)"
    Write-Host "  out got  [$(Show-Escaped $r.out)]"
    Write-Host "  out want [$(Show-Escaped $expOut)]"
    Write-Host "  err got  [$(Show-Escaped $r.err)]"
    Write-Host "  err want [$(Show-Escaped $expErr)]"
  }
}

# Self-guard: zero parsed cases means every row was skipped or the table is
# empty — the suite would otherwise report "0 passed, 0 failed" as a clean,
# misleadingly-green exit.
if ($caseCount -eq 0) {
  Write-Error "FATAL: parsed 0 cases from $Cases — this run tested nothing"
  exit 1
}

# Every assertion below is a bespoke case; the count is derived at the end
# (total assertions minus TSV rows) so a block added here cannot report a stale
# total.
$wsSeq = 0
function New-Workspace {
  $script:wsSeq++
  $p = Join-Path $Tmp "ws$($script:wsSeq)"
  New-Item -ItemType Directory -Path $p | Out-Null
  return $p
}
function Get-Json([string]$path) {
  return ([System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($path, $utf8))).RootElement
}

# ---- write: merge onto an existing canonical cache --------------------------
# Entry 7 is overwritten, entry 11 is added, and entry 9 — which the input never
# mentions — must survive UNTOUCHED, triaged_at byte-for-byte included. That is
# the regression guard for a JSON round-trip that reformats values it does not
# own: ConvertFrom-Json turns "2026-08-01T01:00:00Z" into a [datetime], and
# writing that back rewrites the field in .NET's date format.
# Entry 7's expected key is the LIVE key resp/ts-two.json yields, not the stale
# one entries-two.json supplies: `write` stamps the key itself (issue #462).
# Entry 11 is absent from that response, so it keeps its supplied key — the
# per-issue no-live-key degradation, which writes what it was given rather than
# inventing a key.
$W = New-Workspace
Copy-Item -Path (Join-Path $Fix 'roots' 'hit' '.milestone-config') -Destination $W -Recurse
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$cachePath = Join-Path $W '.milestone-config' 'triage-cache.json'
$okMerge = $false
if ($r.rc -eq 0 -and (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n") -and (Eq-Exact $r.err '')) {
  $c = Get-Json $cachePath
  $names = @($c.EnumerateObject() | ForEach-Object { $_.Name } | Sort-Object)
  $okMerge = ((($names -join ',') -ceq '11,7,9') -and
    ($c.GetProperty('7').GetProperty('key').GetString() -ceq '7:2026-08-01T00:00:00Z:3:alpha,zeta') -and
    ($c.GetProperty('11').GetProperty('key').GetString() -ceq '11:2026-08-02T00:00:00Z:0:') -and
    ($c.GetProperty('9').GetProperty('key').GetString() -ceq '9:STALE-KEY') -and
    ($c.GetProperty('9').GetProperty('triaged_at').GetString() -ceq '2026-08-01T01:00:00Z') -and
    ($c.GetProperty('9').GetProperty('result').GetProperty('edges').GetRawText() -replace '\s', '') -ceq '[100]' -and
    ($c.GetProperty('11').GetProperty('result').GetProperty('risk').GetString() -ceq 'heavy'))
}
if ($okMerge) { Ok } else { No "write-merge: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

# ---- write: self-healed .gitignore is byte-identical to the committed one ----
# The block lives in the script now, so this is what keeps it in sync with
# .milestone-config/.gitignore in this repo — and with the bash twin's copy,
# which the sibling runner asserts against the same file.
if (-not (Test-Path -LiteralPath $RepoGitignore)) { No "write-gitignore: missing $RepoGitignore" }
else {
  $a = [System.IO.File]::ReadAllBytes((Join-Path $W '.milestone-config' '.gitignore'))
  $b = [System.IO.File]::ReadAllBytes($RepoGitignore)
  if ([System.Linq.Enumerable]::SequenceEqual($a, $b)) { Ok }
  else { No "write-gitignore: differs from $RepoGitignore ($($a.Length) vs $($b.Length) bytes)" }
}

# ---- write: an EXISTING .gitignore is never rewritten ------------------------
$W = New-Workspace
New-Item -ItemType Directory -Path (Join-Path $W '.milestone-config') | Out-Null
[System.IO.File]::WriteAllBytes((Join-Path $W '.milestone-config' '.gitignore'), $utf8.GetBytes("sentinel`n"))
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$kept = [System.IO.File]::ReadAllText((Join-Path $W '.milestone-config' '.gitignore'), $utf8)
if ($r.rc -eq 0 -and (Eq-Exact $kept "sentinel`n")) { Ok }
else { No "write-gitignore-preserved: rc=$($r.rc) content=[$(Show-Escaped $kept)]" }

# ---- write: legacy root cache is READ, then REMOVED --------------------------
$W = New-Workspace
Copy-Item -Path (Join-Path $Fix 'roots' 'legacy-only' '.milestone-driver-triage-cache.json') -Destination $W
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$legacyGone = -not (Test-Path -LiteralPath (Join-Path $W '.milestone-driver-triage-cache.json'))
$merged = @()
if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' 'triage-cache.json'))) {
  $merged = @((Get-Json (Join-Path $W '.milestone-config' 'triage-cache.json')).EnumerateObject() |
              ForEach-Object { $_.Name } | Sort-Object)
}
if ($r.rc -eq 0 -and $legacyGone -and (($merged -join ',') -ceq '11,7,9')) { Ok }
else { No "write-legacy-cleanup: rc=$($r.rc) legacyGone=$legacyGone keys=$($merged -join ',')" }

# ---- write: every failure path is exit 0 + one SKIP record -------------------
$W = New-Workspace
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-bad.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
if ($r.rc -eq 0 -and (Eq-Exact $r.out "SKIP${TAB}bad-entries`n") -and (Eq-Exact $r.err '') -and
    -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config' 'triage-cache.json'))) { Ok }
else { No "write-bad-entries: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

$W = New-Workspace
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'does-not-exist.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
if ($r.rc -eq 0 -and (Eq-Exact $r.out "SKIP${TAB}bad-entries`n") -and (Eq-Exact $r.err '')) { Ok }
else { No "write-missing-entries: rc=$($r.rc) out=[$(Show-Escaped $r.out)]" }

# A regular FILE occupying .milestone-config/ is where `mkdir -p` fails on the
# bash leg. New-Item -Force does NOT throw there, so this case is what holds the
# two legs to the same mkdir-failed record.
$W = New-Workspace
[System.IO.File]::WriteAllBytes((Join-Path $W '.milestone-config'), $utf8.GetBytes(''))
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
if ($r.rc -eq 0 -and (Eq-Exact $r.out "SKIP${TAB}mkdir-failed`n") -and (Eq-Exact $r.err '')) { Ok }
else { No "write-mkdir-failed: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

# A READ-ONLY .milestone-config/ lets the directory create succeed and fails the
# write itself. chmod bites on the CI (Linux) leg; where perms don't bite (some
# Windows FS / root) the write succeeds and we skip rather than false-fail.
$W = New-Workspace
$ro = Join-Path $W '.milestone-config'
New-Item -ItemType Directory -Path $ro | Out-Null
if ($IsWindows) { $chmodOk = $false } else { chmod 555 $ro; $chmodOk = $true }
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
if (-not $chmodOk -or (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n")) { Ok }
elseif ($r.rc -eq 0 -and (Eq-Exact $r.out "SKIP${TAB}write-failed`n") -and (Eq-Exact $r.err '')) { Ok }
else { No "write-failed: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }
if ($chmodOk) { chmod 755 $ro }

# ---- write -> lookup round trip: what write stores is what lookup compares ---
# entries-two.json supplies a deliberately STALE key for issue 7, so a HIT here
# is only reachable because `write` recomputed the key from the same response
# Step 2.5 hands `lookup` — the "one definition, not two" guard (issue #462).
# The other three records are the rest of the observed stream: issue 9 is in the
# response but not in the entries, so it keeps the root's `9:STALE-KEY` and
# misses; and EDGES carries 100 alone because entry 7 was fully overwritten from
# entries-two.json's `result.edges: [100]`, not merged with the root's [100,101].
$W = New-Workspace
Copy-Item -Path (Join-Path $Fix 'roots' 'hit' '.milestone-config') -Destination $W -Recurse
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$rt = Invoke-Tc @('lookup', $W, (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$rtWant = "HIT${TAB}7`nMISS${TAB}9${TAB}key-mismatch`nEDGES${TAB}100`nSUMMARY${TAB}hits=1${TAB}misses=1`n"
if ($r.rc -eq 0 -and (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n") -and
    $rt.rc -eq 0 -and (Eq-Exact $rt.out $rtWant) -and (Eq-Exact $rt.err '')) { Ok }
else { No "write-lookup-roundtrip: rc=$($r.rc) out=[$(Show-Escaped $r.out)] lookup_rc=$($rt.rc) lookup=[$(Show-Escaped $rt.out)] err=[$(Show-Escaped $rt.err)]" }

# ---- write: the KEY-LESS entries object Step 6.5 actually builds -------------
# skills/triage/SKILL.md Step 6.5 forbids the caller from computing a key, so
# the shape production hands `write` carries NONE. Every other fixture here
# supplies one, which exercises only the REPLACE half of the stamp; this case is
# the only cover for the APPEND half (`if (-not $wroteKey)`). Issue 7 is in the
# response and gets a key appended (and then HITs); issue 11 is not, and stays
# key-less rather than being handed an invented one.
$W = New-Workspace
Copy-Item -Path (Join-Path $Fix 'roots' 'hit' '.milestone-config') -Destination $W -Recurse
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-keyless.json'), (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$kl = Invoke-Tc @('lookup', $W, (Join-Path $Fix 'resp' 'ts-two.json')) $Tmp
$okKeyless = $false
if ($r.rc -eq 0 -and (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n") -and (Eq-Exact $r.err '')) {
  $c = Get-Json (Join-Path $W '.milestone-config' 'triage-cache.json')
  # Property-presence FIRST, then read: entry 7 carrying no `key` is the exact
  # regression this case exists to catch, and GetProperty THROWS on an absent
  # one — under $ErrorActionPreference='Stop' that aborts the whole runner
  # instead of reporting one FAIL, hiding every case below it.
  $has11Key = @($c.GetProperty('11').EnumerateObject() | ForEach-Object { $_.Name }) -ccontains 'key'
  $key7 = ''
  if (@($c.GetProperty('7').EnumerateObject() | ForEach-Object { $_.Name }) -ccontains 'key') {
    $key7 = $c.GetProperty('7').GetProperty('key').GetString()
  }
  $okKeyless = (($key7 -ceq '7:2026-08-01T00:00:00Z:3:alpha,zeta') -and
    (-not $has11Key) -and
    ($c.GetProperty('11').GetProperty('result').GetProperty('risk').GetString() -ceq 'heavy') -and
    ($c.GetProperty('9').GetProperty('triaged_at').GetString() -ceq '2026-08-01T01:00:00Z') -and
    $kl.out.StartsWith("HIT${TAB}7`n"))
}
if ($okKeyless) { Ok }
else { No "write-keyless-entries: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)] lookup=[$(Show-Escaped $kl.out)]" }

# ---- write with THREE arguments is usage/exit 2, never a 3-arg write ---------
# NOT a TSV row, even though it is a pure usage case: every row runs against a
# COMMITTED fixture root, and this one MUTATED roots/hit while it was being
# written — the pre-fix script accepted the 3-arg form and wrote the cache. A
# temp root is the only safe home for a `write` case, and it also asserts the
# thing the table cannot: that nothing was written.
$W = New-Workspace
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json')) $Tmp
$wantErr = (Read-Golden (Join-Path $Gold 'usage.err')) -replace '__SCRIPT__', $ScriptName
if ($r.rc -eq 2 -and (Eq-Exact $r.out '') -and (Eq-Exact $r.err $wantErr) -and
    -not (Test-Path -LiteralPath (Join-Path $W '.milestone-config'))) { Ok }
else { No "write-wrong-argc: rc=$($r.rc) (want 2) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

# ---- write: an ABSENT response is the fail-open degradation, not a failure ----
# No live key for any issue, so every entry is stored exactly as supplied — no
# new SKIP reason, still exit 0, and no key invented from thin air.
$W = New-Workspace
$r = Invoke-Tc @('write', $W, (Join-Path $Fix 'entries-two.json'), (Join-Path $Fix 'resp' 'absent.json')) $Tmp
$keptKey = ''
if ($r.rc -eq 0 -and (Test-Path -LiteralPath (Join-Path $W '.milestone-config' 'triage-cache.json'))) {
  $keptKey = (Get-Json (Join-Path $W '.milestone-config' 'triage-cache.json')).GetProperty('7').GetProperty('key').GetString()
}
if ($r.rc -eq 0 -and (Eq-Exact $r.out "OK$TAB.milestone-config/triage-cache.json`n") -and (Eq-Exact $r.err '') -and
    ($keptKey -ceq '7:2026-08-02T00:00:00Z:4:alpha,zeta')) { Ok }
else { No "write-absent-response: rc=$($r.rc) out=[$(Show-Escaped $r.out)] key=[$keptKey]" }

# ---- pwsh-only: no external tool is consulted --------------------------------
# The bash twin's mirror case asserts SKIP no-jq with PATH emptied. This leg has
# no such record to emit, and the claim behind that difference — "this twin
# needs no external tool" — is only worth as much as an assertion. Same input,
# same golden, PATH empty in the child.
$r = Invoke-Tc @('lookup', (Join-Path $Fix 'roots' 'hit'), (Join-Path $Fix 'resp' 'ts-two.json')) $Fix ''
$expOut = Read-Golden (Join-Path $Gold 'lookup-hit.out')
if ($r.rc -eq 0 -and (Eq-Exact $r.out $expOut) -and (Eq-Exact $r.err '')) { Ok }
else { No "empty-PATH-lookup: rc=$($r.rc) out=[$(Show-Escaped $r.out)] err=[$(Show-Escaped $r.err)]" }

if (-not $IsWindows) { chmod -R u+w $Tmp 2>$null }
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
$bespoke = $pass + $fail - $caseCount
Write-Host "triage-cache.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + $bespoke bespoke)"
if ($fail -ne 0) { exit 1 }
