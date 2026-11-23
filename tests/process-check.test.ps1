#!/usr/bin/env pwsh
# milestone-driver - behavior matrix runner for process-check.{sh,ps1} (issue #791).
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_lib.ps1'); Set-Leg $Leg
$plugin = (Resolve-Path (Join-Path $here '..')).Path
$script = Join-Path $plugin 'scripts' 'process-check'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$pass = 0; $fail = 0
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("pck_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null

function New-Ws { $w = Join-Path $root ([System.Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $w | Out-Null; return $w }
function Put([string]$ws, [string]$rel, [string]$text) {
  $p = Join-Path $ws $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
  [System.IO.File]::WriteAllText($p, $text, $utf8)
}
function Marker-Path([string]$ws) { Join-Path $ws '.milestone-config/.runtime/process-check.json' }
function Marker-Text([string]$ws) {
  $p = Marker-Path $ws
  if (Test-Path -LiteralPath $p -PathType Leaf) { return [System.IO.File]::ReadAllText($p, $utf8) } else { return $null }
}
function Run([string[]]$cliArgs, [string]$script_ = $script, [hashtable]$envOverride = @{}) {
  return Invoke-Leg -Script $script_ -Args $cliArgs -Env $envOverride
}
function Status([string]$ws) { return Run @('--status', $ws) }
function Record([string]$ws, [string]$outcome = 'clean') { return Run @('--record', $outcome, $ws) }
function Err-Lines($err) { @($err -split "`r?`n" | Where-Object { $_ -ne '' }).Count }

function Expect([string]$name, $r, [string]$wantOut, [int]$wantRc = 0, [string]$wantErr = '') {
  $wantErrText = if ($wantErr) { $wantErr + "`n" } else { '' }
  if ($r.rc -eq $wantRc -and $r.out -ceq $wantOut -and $r.err -ceq $wantErrText) { $script:pass++ }
  else { $script:fail++; Write-Host "FAIL $name rc=$($r.rc) (want $wantRc) out=[$($r.out)] (want [$wantOut]) err=[$($r.err)] (want [$wantErrText])" }
}
function Check([string]$name, [bool]$cond, [string]$detail = '') {
  if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name $detail" }
}

# The citation gate reads a quoted path-hash-word as a heading citation; these are profile fixtures.
$H = '#'
$USAGE = 'process-check: usage: process-check (--status | --record <clean|updated|declined>) <repo-root>'

try {
  # ---- no marker: due, exit 0 ----------------------------------------------
  $ws = New-Ws; Put $ws 'CLAUDE.md' "rules`n"
  Expect 'no-marker' (Status $ws) "due`n"

  # ---- record: silent, writes the marker, next status is current -----------
  $r = Record $ws 'clean'
  Expect 'record-silent' $r ''
  $m = Marker-Text $ws
  Check 'record-bytes' ($m -cmatch '^\{"hash":"[0-9a-f]{40}","outcome":"clean"\}\n$') "marker=[$m]"
  Expect 'status-after-record' (Status $ws) "current`n"
  $hash = if ($m -cmatch '"hash":"([0-9a-f]{40})"') { $Matches[1] } else { '' }

  # ---- marker hash equal to the digest is current whatever the outcome -----
  [System.IO.File]::WriteAllText((Marker-Path $ws), "{`"outcome`":`"x`",`"hash`":`"$hash`"}`n", $utf8)
  Expect 'hash-only-compared' (Status $ws) "current`n"

  # ---- changed / newly present / removed scanned file ----------------------
  Record $ws 'clean' | Out-Null
  Put $ws 'CLAUDE.md' "rules changed`n"
  Expect 'changed-file' (Status $ws) "due`n"
  Record $ws 'updated' | Out-Null
  Put $ws 'AGENTS.md' "new`n"
  Expect 'new-file' (Status $ws) "due`n"
  Record $ws 'updated' | Out-Null
  Remove-Item -LiteralPath (Join-Path $ws 'AGENTS.md')
  Expect 'removed-file' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Put $ws '.claude/CLAUDE.md' "nested`n"
  Expect 'claude-dir-file' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Put $ws '.project/conventions.md' "c`n"
  Expect 'project-md' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null

  # ---- a changed file outside the scanned list stays current ---------------
  Put $ws 'README.md' "readme`n"
  Put $ws '.project/notes.txt' "not markdown`n"
  Put $ws '.project/sub/deep.md' "below the directory`n"
  Expect 'unscanned-file' (Status $ws) "current`n"

  # ---- declined with an unchanged digest stays current ---------------------
  $ws = New-Ws; Put $ws 'CLAUDE.md' "a`n"
  Expect 'record-declined' (Record $ws 'declined') ''
  Check 'declined-outcome' ((Marker-Text $ws) -cmatch '"outcome":"declined"\}\n$')
  Expect 'declined-current' (Status $ws) "current`n"
  Put $ws 'CLAUDE.md' "b`n"
  Expect 'declined-then-changed' (Status $ws) "due`n"

  # ---- every absent optional file: still a status, exit 0 ------------------
  $ws = New-Ws
  Expect 'all-absent-status' (Status $ws) "due`n"
  Expect 'all-absent-record' (Record $ws 'clean') ''
  Expect 'all-absent-current' (Status $ws) "current`n"

  # ---- projectDocs directory and standingDocs paths are scanned ------------
  $ws = New-Ws
  Put $ws '.milestone-config/driver.json' ('{"projectDocs":"docs/pd/","standingDocs":["rules.md' + $H + 'Naming","sub/deep.md' + $H + 'Top","rules.md' + $H + 'Other",7]}')
  Put $ws 'docs/pd/rules.md' "r`n"
  Put $ws 'docs/pd/sub/deep.md' "d`n"
  Put $ws 'docs/pd/skip.txt' "t`n"
  Record $ws 'clean' | Out-Null
  Expect 'pd-recorded' (Status $ws) "current`n"
  Put $ws 'docs/pd/rules.md' "r2`n"
  Expect 'projectDocs-dir-file' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Put $ws 'docs/pd/sub/deep.md' "d2`n"
  Expect 'standingDocs-path' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Put $ws 'docs/pd/skip.txt' "t2`n"
  Expect 'projectDocs-nonmd' (Status $ws) "current`n"
  Put $ws '.project/own.md' "default dir still scanned`n"
  Expect 'project-dir-beside-projectDocs' (Status $ws) "due`n"

  # ---- standingDocs without projectDocs resolves under .project/ -----------
  $ws = New-Ws
  Put $ws '.milestone-config/driver.json' ('{"standingDocs":["sub/deep.md' + $H + 'Top"]}')
  Put $ws '.project/sub/deep.md' "d`n"
  Record $ws 'clean' | Out-Null
  Put $ws '.project/sub/deep.md' "d2`n"
  Expect 'standingDocs-default-dir' (Status $ws) "due`n"

  # ---- the digest is git's blob hash over the byte-sorted manifest ---------
  $ws = New-Ws
  foreach ($f in @('CLAUDE.md', 'AGENTS.md', '.claude/CLAUDE.md', '.project/B.md', '.project/a.md', ".project/$([char]0xE9).md")) { Put $ws $f "body of $f`n" }
  Record $ws 'clean' | Out-Null
  $blob = { param($p) (& git hash-object --no-filters -- $p).Trim() }
  $manifest = "contract $(& $blob (Join-Path $plugin 'skills/process-check.md'))`n"
  foreach ($f in @('.claude/CLAUDE.md', '.project/B.md', '.project/a.md', ".project/$([char]0xE9).md", 'AGENTS.md', 'CLAUDE.md')) {
    $manifest += "$(& $blob (Join-Path $ws $f)) $f`n"
  }
  $psi = [System.Diagnostics.ProcessStartInfo]::new('git')
  [void]$psi.ArgumentList.Add('hash-object'); [void]$psi.ArgumentList.Add('--stdin')
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $bytes = $utf8.GetBytes($manifest); $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length); $p.StandardInput.Close()
  $want = $p.StandardOutput.ReadToEnd().Trim(); $p.WaitForExit()
  Check 'digest-manifest' ((Marker-Text $ws) -ceq "{`"hash`":`"$want`",`"outcome`":`"clean`"}`n") "marker=[$(Marker-Text $ws)] want=$want"

  # ---- unusable markers read as due ----------------------------------------
  $ws = New-Ws; Put $ws 'CLAUDE.md' "a`n"
  Record $ws 'clean' | Out-Null
  foreach ($bad in @('not json', '{"hash":5}', '{"hash":null}', '[]', '{}', '{"outcome":"clean"}', '[{"hash":"x"}]', '"abc"', '', '{"hash":"x"} {"hash":"y"}')) {
    [System.IO.File]::WriteAllText((Marker-Path $ws), $bad, $utf8)
    Expect "bad-marker [$bad]" (Status $ws) "due`n"
  }
  Remove-Item -LiteralPath (Marker-Path $ws)
  New-Item -ItemType Directory -Path (Marker-Path $ws) | Out-Null
  Expect 'marker-is-directory' (Status $ws) "due`n"

  # ---- changed contract bytes (a copy of the twins in a temp plugin tree) --
  $pt = New-Ws
  New-Item -ItemType Directory -Force -Path (Join-Path $pt 'scripts'), (Join-Path $pt 'skills') | Out-Null
  foreach ($e in @('sh', 'ps1')) { Copy-Item -LiteralPath (Join-Path $plugin "scripts/process-check.$e") -Destination (Join-Path $pt 'scripts') }
  Copy-Item -LiteralPath (Join-Path $plugin 'skills/process-check.md') -Destination (Join-Path $pt 'skills')
  $tscript = Join-Path $pt 'scripts' 'process-check'
  $ws = New-Ws; Put $ws 'CLAUDE.md' "a`n"
  Expect 'contract-record' (Run @('--record', 'clean', $ws) $tscript) ''
  Expect 'contract-current' (Run @('--status', $ws) $tscript) "current`n"
  [System.IO.File]::AppendAllText((Join-Path $pt 'skills/process-check.md'), "extra row`n", $utf8)
  Expect 'contract-changed' (Run @('--status', $ws) $tscript) "due`n"
  Remove-Item -LiteralPath (Join-Path $pt 'skills/process-check.md')
  Expect 'contract-unreadable' (Run @('--status', $ws) $tscript) '' 1 'process-check: cannot read skills/process-check.md'

  # ---- environment failures: exit 1, nothing on stdout, one stderr line ----
  $ws = New-Ws; Put $ws '.milestone-config/driver.json' '{ not json'
  Expect 'profile-unparseable' (Status $ws) '' 1 'process-check: cannot read .milestone-config/driver.json'
  Expect 'profile-unparseable-record' (Record $ws) '' 1 'process-check: cannot read .milestone-config/driver.json'
  Put $ws '.milestone-config/driver.json' '[]'
  Expect 'profile-not-object' (Status $ws) '' 1 'process-check: cannot read .milestone-config/driver.json'
  Remove-Item -Force -LiteralPath (Join-Path $ws '.milestone-config/driver.json')
  New-Item -ItemType Directory -Path (Join-Path $ws '.milestone-config/driver.json') | Out-Null
  Expect 'profile-is-directory' (Status $ws) '' 1 'process-check: cannot read .milestone-config/driver.json'

  $ws = New-Ws; Put $ws 'CLAUDE.md' "a`n"
  Put $ws '.milestone-config/.runtime' 'a file where the directory must go'
  Expect 'runtime-uncreatable' (Record $ws) '' 1 'process-check: cannot write .milestone-config/.runtime/process-check.json'
  Check 'runtime-uncreatable-no-marker' (@(Get-ChildItem -LiteralPath (Join-Path $ws '.milestone-config') -Recurse -File -Force | Where-Object { $_.Name -ne '.runtime' }).Count -eq 0)

  $ws = New-Ws; Put $ws 'CLAUDE.md' "a`n"
  New-Item -ItemType Directory -Path (Marker-Path $ws) | Out-Null
  Expect 'marker-path-is-directory-record' (Record $ws) '' 1 'process-check: cannot write .milestone-config/.runtime/process-check.json'
  Check 'marker-dir-untouched' (@(Get-ChildItem -LiteralPath (Marker-Path $ws) -Force).Count -eq 0)

  # ---- usage: exit 2, one stderr line, nothing on stdout -------------------
  $ws = New-Ws
  Expect 'usage-no-args' (Run @()) '' 2 $USAGE
  Expect 'usage-unknown-mode' (Run @('--bogus', $ws)) '' 2 $USAGE
  Expect 'usage-status-no-root' (Run @('--status')) '' 2 $USAGE
  Expect 'usage-status-extra' (Run @('--status', $ws, 'x')) '' 2 $USAGE
  Expect 'usage-record-no-outcome' (Run @('--record')) '' 2 $USAGE
  Expect 'usage-record-no-root' (Run @('--record', 'clean')) '' 2 $USAGE
  Expect 'usage-bad-outcome' (Run @('--record', 'maybe', $ws)) '' 2 $USAGE
  Expect 'usage-empty-root' (Run @('--status', '')) '' 2 $USAGE
  Expect 'usage-root-not-a-dir' (Run @('--status', (Join-Path $ws 'nope'))) '' 2 $USAGE
  Check 'usage-record-writes-nothing' ($null -eq (Marker-Text $ws))

  # ---- bash leg only: jq is the JSON parser, usage still wins --------------
  if ($Leg -eq 'sh') {
    $nojq = Join-Path $root 'nojq'
    New-Item -ItemType Directory -Force -Path $nojq | Out-Null
    $ws = New-Ws
    Expect 'jq-missing-status' (Run @('--status', $ws) $script @{ PATH = $nojq }) '' 1 'process-check: jq is required but not on PATH'
    Expect 'jq-missing-record' (Run @('--record', 'clean', $ws) $script @{ PATH = $nojq }) '' 1 'process-check: jq is required but not on PATH'
    Expect 'jq-missing-usage-first' (Run @('--status') $script @{ PATH = $nojq }) '' 2 $USAGE
  }
}
finally {
  Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

Write-Host "process-check ($Leg): $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
