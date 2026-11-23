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

function Expect([string]$name, $r, [string]$wantOut, [int]$wantRc = 0, [string]$wantErr = '') {
  $wantErrText = if ($wantErr) { $wantErr + "`n" } else { '' }
  if ($r.rc -eq $wantRc -and $r.out -ceq $wantOut -and $r.err -ceq $wantErrText) { $script:pass++ }
  else { $script:fail++; Write-Host "FAIL $name rc=$($r.rc) (want $wantRc) out=[$($r.out)] (want [$wantOut]) err=[$($r.err)] (want [$wantErrText])" }
}
function Check([string]$name, [bool]$cond, [string]$detail = '') {
  if ($cond) { $script:pass++ } else { $script:fail++; Write-Host "FAIL $name $detail" }
}
# The manifest's key lines, in order: one `key <name> <raw string value>` line per present string-valued profile key without a control character.
$CONTRACT_KEYS = @('integrationGranularity', 'implementerAgent', 'unitTestCmd', 'e2eTestCmd', 'preflightCmd', 'coherenceReviewAgent')
function Key-Lines([string]$profilePath) {
  $out = ''
  if (-not $profilePath) { return $out }
  $doc = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($profilePath, $utf8))
  try {
    foreach ($k in $CONTRACT_KEYS) {
      $v = [System.Text.Json.JsonElement]::new()
      if ($doc.RootElement.TryGetProperty($k, [ref]$v) -and $v.ValueKind -eq 'String' -and $v.GetString() -cnotmatch '[\x00-\x1f]') { $out += "key $k $($v.GetString())`n" }
    }
    return $out
  } finally { $doc.Dispose() }
}
# The marker text a digest over the contract, the profile's contract keys (when a profile exists), the declined file (when present) and these workspace-relative paths (already in byte order) must produce.
function Expected-Marker([string]$ws, [string[]]$relsInOrder, [string]$outcome = 'clean') {
  $blob = { param($p) (& git hash-object --no-filters -- $p).Trim() }
  $manifest = "contract $(& $blob (Join-Path $plugin 'skills/process-check.md'))`n"
  $prof = @('.milestone-config/driver.json', 'milestone-driver.json') | Where-Object { Test-Path -LiteralPath (Join-Path $ws $_) } | Select-Object -First 1
  $manifest += Key-Lines $(if ($prof) { Join-Path $ws $prof } else { '' })
  $dp = Join-Path $ws '.milestone-config/.runtime/process-check-declined.json'
  if (Test-Path -LiteralPath $dp -PathType Leaf) { $manifest += "declined $(& $blob $dp)`n" }
  foreach ($f in $relsInOrder) { $manifest += "$(& $blob (Join-Path $ws $f)) $f`n" }
  $h = (Invoke-Child -Exe 'git' -Argv @('hash-object', '--stdin') -Stdin $manifest -Cwd '' -Env @{}).out.Trim()
  return "{`"hash`":`"$h`",`"outcome`":`"$outcome`"}`n"
}

# The citation gate reads a quoted path-hash-word as a heading citation; these are profile fixtures.
$H = '#'
$USAGE = 'process-check: usage: process-check (--status | --record <clean|declined>) <repo-root>'

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
  Record $ws 'clean' | Out-Null
  Put $ws 'AGENTS.md' "new`n"
  Expect 'new-file' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
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

  # ---- the declined file joins the digest: deleting or changing it makes the next status due ----
  $ws = New-Ws; Put $ws 'CLAUDE.md' "a`n"
  $dpath = '.milestone-config/.runtime/process-check-declined.json'
  Expect 'declined-absent-record' (Record $ws 'declined') ''
  $absentMarker = Marker-Text $ws
  Check 'declined-absent-omitted' ($absentMarker -ceq (Expected-Marker $ws @('CLAUDE.md') 'declined')) "marker=[$absentMarker]"
  Expect 'declined-absent-current' (Status $ws) "current`n"
  Put $ws $dpath '{"declined":[{"file":"CLAUDE.md","quote":"a"}]}'
  Expect 'declined-file-added-due' (Status $ws) "due`n"
  Expect 'declined-present-record' (Record $ws 'declined') ''
  Check 'declined-present-digest' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md') 'declined')) "marker=[$(Marker-Text $ws)]"
  Check 'declined-present-differs-from-absent' ((Marker-Text $ws) -cne $absentMarker)
  Expect 'declined-present-current' (Status $ws) "current`n"
  Put $ws $dpath '{"declined":[]}'
  Expect 'declined-file-changed-due' (Status $ws) "due`n"
  Record $ws 'declined' | Out-Null
  Expect 'declined-rewritten-current' (Status $ws) "current`n"
  Remove-Item -LiteralPath (Join-Path $ws $dpath)
  Expect 'declined-file-deleted-due' (Status $ws) "due`n"
  Record $ws 'declined' | Out-Null
  Check 'declined-deleted-equals-absent' ((Marker-Text $ws) -ceq $absentMarker) "marker=[$(Marker-Text $ws)]"
  New-Item -ItemType Directory -Force -Path (Join-Path $ws $dpath) | Out-Null
  Expect 'declined-path-is-directory-ignored' (Status $ws) "current`n"

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
  $want = (Invoke-Child -Exe 'git' -Argv @('hash-object', '--stdin') -Stdin $manifest -Cwd '' -Env @{}).out.Trim()
  Check 'digest-manifest' ((Marker-Text $ws) -ceq "{`"hash`":`"$want`",`"outcome`":`"clean`"}`n") "marker=[$(Marker-Text $ws)] want=$want"

  # ---- paths that differ only by case stay two manifest lines, as `sort -u` keeps them ----
  # On a case-insensitive filesystem .project/A.md is the file .project/a.md; the digest still lists both names.
  $ws = New-Ws
  Put $ws '.project/a.md' "lower`n"
  if (-not (Test-Path -LiteralPath (Join-Path $ws '.project/A.md'))) { Put $ws '.project/A.md' "upper`n" }
  Put $ws '.milestone-config/driver.json' '{"standingDocs":["A.md"]}'
  Record $ws 'clean' | Out-Null
  Check 'case-only-paths-both-listed' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('.project/A.md', '.project/a.md'))) "marker=[$(Marker-Text $ws)]"
  Expect 'case-only-paths-current' (Status $ws) "current`n"

  # ---- JSON keys differing only by case: jq accepts them, so both legs must ----
  $ws = New-Ws
  Put $ws '.milestone-config/driver.json' '{"projectDocs":"docs","ProjectDocs":"y"}'
  Put $ws 'docs/x.md' "x`n"
  Expect 'profile-case-keys-status' (Status $ws) "due`n"
  Expect 'profile-case-keys-record' (Record $ws 'clean') ''
  Check 'profile-case-keys-uses-exact-key' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('docs/x.md'))) "marker=[$(Marker-Text $ws)]"
  $hash = if ((Marker-Text $ws) -cmatch '"hash":"([0-9a-f]{40})"') { $Matches[1] } else { '' }
  [System.IO.File]::WriteAllText((Marker-Path $ws), "{`"hash`":`"$hash`",`"Hash`":`"zzz`"}`n", $utf8)
  Expect 'marker-case-keys-exact' (Status $ws) "current`n"

  # ---- a legacy root milestone-driver.json is the profile when .milestone-config/driver.json is absent ----
  $ws = New-Ws
  Put $ws 'milestone-driver.json' '{"projectDocs":"docs/pd"}'
  Put $ws 'docs/pd/x.md' "x`n"
  Record $ws 'clean' | Out-Null
  Check 'legacy-profile-hashes-projectDocs' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('docs/pd/x.md'))) "marker=[$(Marker-Text $ws)]"
  Expect 'legacy-profile-current' (Status $ws) "current`n"
  # both present: .milestone-config/driver.json wins
  Put $ws '.milestone-config/driver.json' '{"projectDocs":"docs/other"}'
  Put $ws 'docs/other/y.md' "y`n"
  Record $ws 'clean' | Out-Null
  Check 'legacy-profile-loses-to-canonical' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('docs/other/y.md'))) "marker=[$(Marker-Text $ws)]"
  # an unusable legacy profile names itself
  $ws = New-Ws; Put $ws 'milestone-driver.json' '{ not json'
  Expect 'legacy-profile-unparseable' (Status $ws) '' 1 'process-check: cannot read milestone-driver.json'

  # ---- the profile's contract keys join the digest, and nothing else in it does: the auditor judges keyed rows against those keys ----
  $ws = New-Ws
  Put $ws '.milestone-config/driver.json' '{"unitTestCmd":"t","e2eTestCmd":5,"preflightCmd":null,"implementerAgent":["x"]}'
  Put $ws 'CLAUDE.md' "a`n"
  Record $ws 'clean' | Out-Null
  Check 'profile-keys-in-digest' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"
  Expect 'profile-recorded-current' (Status $ws) "current`n"
  Put $ws '.milestone-config/driver.json' '{"unitTestCmd":"t","e2eTestCmd":5,"preflightCmd":null,"implementerAgent":["x"],"parallel":false}'
  Expect 'profile-parallel-added-current' (Status $ws) "current`n"
  Put $ws '.milestone-config/driver.json' '{"unitTestCmd":"t","e2eTestCmd":9,"preflightCmd":false,"implementerAgent":{"a":1}}'
  Expect 'profile-nonstring-keys-current' (Status $ws) "current`n"
  Put $ws '.milestone-config/driver.json' '{"unitTestCmd":"t2"}'
  Expect 'profile-key-changed' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Check 'profile-changed-digest' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"
  Expect 'profile-rerecorded-current' (Status $ws) "current`n"
  Put $ws '.milestone-config/driver.json' '{"unitTestCmd":"t2","UnitTestCmd":"x"}'
  Expect 'profile-key-case-exact-current' (Status $ws) "current`n"
  # raw value bytes (non-ASCII, quote, backslash, embedded newline, trailing newline) hash the same on both legs
  Put $ws '.milestone-config/driver.json' ('{"preflightCmd":"p ' + [char]0xE9 + ' \"q\" \\ \nz","coherenceReviewAgent":"c\n"}')
  Record $ws 'clean' | Out-Null
  Check 'profile-raw-value-bytes' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"

  # a value holding U+0000 is omitted like a non-string, so bash command substitution (which drops NUL) and the .ps1 twin hash alike, with nothing on stderr
  Put $ws '.milestone-config/driver.json' '{"unitTestCmd":"a\u0000b","preflightCmd":"p"}'
  Expect 'profile-nul-value-record' (Record $ws) ''
  Check 'profile-nul-value-omitted' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"

  # NUL, CR, LF and other control characters inside a contract-key value omit that key on both legs, so a CRLF-emitting jq or a value that splits a line cannot make the twins hash differently
  Put $ws '.milestone-config/driver.json' '{"unitTestCmd":"a\nb","e2eTestCmd":"a\rb","preflightCmd":"a\u0000b","implementerAgent":"a\tb","coherenceReviewAgent":"ok"}'
  Expect 'profile-control-values-record' (Record $ws) ''
  Check 'profile-control-values-omitted' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"
  foreach ($c in @('\u0000', '\r', '\n')) {
    Put $ws '.milestone-config/driver.json' ('{"unitTestCmd":"a' + $c + 'b"}')
    $r1 = Record $ws; $m1 = Marker-Text $ws
    Put $ws '.milestone-config/driver.json' '{}'
    $r2 = Record $ws; $m2 = Marker-Text $ws
    Check "key-with-$c-same-as-absent" ($r1.rc -eq 0 -and $r2.rc -eq 0 -and $m1 -ceq $m2) "m1=[$m1] m2=[$m2]"
  }

  # a projectDocs value with a control character falls back to .project, and a standingDocs entry with one is omitted, not split into two paths
  $ws = New-Ws
  Put $ws '.milestone-config/driver.json' '{"projectDocs":"docs\nx","standingDocs":["s.md"]}'
  Put $ws '.project/s.md' "s`n"
  Put $ws 'docs/s.md' "not scanned`n"
  Record $ws | Out-Null
  Check 'projectDocs-lf-falls-back' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('.project/s.md'))) "marker=[$(Marker-Text $ws)]"
  $ws = New-Ws
  Put $ws '.milestone-config/driver.json' '{"standingDocs":["sub/a.md\nsub/b.md","sub/c.md\rx","sub/ok.md"]}'
  foreach ($f in @('a', 'b', 'c', 'ok')) { Put $ws ".project/sub/$f.md" "$f`n" }
  Record $ws | Out-Null
  Check 'standingDocs-control-entry-omitted' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('.project/sub/ok.md'))) "marker=[$(Marker-Text $ws)]"

  # a scanned filename with a control character is skipped by both legs; its tail after the LF names a real file (README.md) that must not join the manifest
  $ws = New-Ws
  Put $ws 'CLAUDE.md' "c`n"
  Put $ws 'README.md' "not scanned`n"
  Put $ws '.project/ok.md' "ok`n"
  $lfPath = Join-Path $ws ".project/q$([char]10)README.md"
  try { [System.IO.File]::WriteAllText($lfPath, "x`n", $utf8) } catch { }
  if (Test-Path -LiteralPath $lfPath -PathType Leaf) {
    Record $ws | Out-Null
    Check 'scanned-lf-filename-ignored' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('.project/ok.md', 'CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"
  }

  # ---- integrationGranularity is the profile's raw string, hashed like the other contract keys ----
  $ws = New-Ws
  Put $ws 'CLAUDE.md' "a`n"
  Record $ws 'clean' | Out-Null
  $absent = Marker-Text $ws
  Put $ws '.milestone-config/driver.json' '{"integrationGranularity":"issue"}'
  Expect 'granularity-added-due' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Check 'granularity-issue-digest' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"
  Check 'granularity-issue-differs-from-absent' ((Marker-Text $ws) -cne $absent)
  Expect 'granularity-same-current' (Status $ws) "current`n"
  Put $ws '.milestone-config/driver.json' '{"integrationGranularity":"wave"}'
  Expect 'granularity-changed-due' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Check 'granularity-wave-digest' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"
  Expect 'granularity-wave-current' (Status $ws) "current`n"
  Put $ws '.milestone-config/driver.json' '{"integrationGranularity":"Wave"}'
  Expect 'granularity-raw-case-due' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Check 'granularity-raw-value-digest' ((Marker-Text $ws) -ceq (Expected-Marker $ws @('CLAUDE.md'))) "marker=[$(Marker-Text $ws)]"
  Put $ws '.milestone-config/driver.json' '{}'
  Expect 'granularity-removed-due' (Status $ws) "due`n"
  Record $ws 'clean' | Out-Null
  Check 'granularity-removed-equals-absent' ((Marker-Text $ws) -ceq $absent) "marker=[$(Marker-Text $ws)]"
  Put $ws '.milestone-config/driver.json' '{"integrationGranularity":5}'
  Expect 'granularity-nonstring-omitted' (Status $ws) "current`n"
  Put $ws '.milestone-config/driver.json' '{"integrationGranularity":"x\ny"}'
  Expect 'granularity-control-value-omitted' (Status $ws) "current`n"

  # ---- an empty standingDocs entry names no file ------------------------------
  $ws = New-Ws
  Put $ws '.milestone-config/driver.json' '{"standingDocs":[""]}'
  Put $ws '.project/null' "a file literally named null`n"
  Record $ws 'clean' | Out-Null
  Check 'standingDocs-empty-entry-skipped' ((Marker-Text $ws) -ceq (Expected-Marker $ws @())) "marker=[$(Marker-Text $ws)]"

  # ---- the marker lives under the main repo root: a linked worktree and the main checkout share it ----
  $git = { param($d, [string[]]$a) (Invoke-Child -Exe 'git' -Argv (@('-C', $d) + $a) -Stdin '' -Cwd '' -Env @{}) }
  $main = New-Ws
  & $git $main @('init', '-q') | Out-Null
  & $git $main @('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '--allow-empty', '-m', 'x') | Out-Null
  $mainReal = (& $git $main @('rev-parse', '--show-toplevel')).out.Trim()
  $wt = Join-Path $root ([System.Guid]::NewGuid().ToString('N'))
  $added = & $git $main @('worktree', 'add', '-q', '--detach', $wt)
  Check 'worktree-added' ($added.rc -eq 0) "err=[$($added.err)]"
  foreach ($d in @($main, $wt)) { Put $d 'CLAUDE.md' "same rules`n" }
  Expect 'worktree-record' (Record $wt 'clean') ''
  Check 'worktree-marker-under-main' (Test-Path -LiteralPath (Join-Path $mainReal '.milestone-config/.runtime/process-check.json') -PathType Leaf)
  Check 'worktree-no-own-marker' ($null -eq (Marker-Text $wt))
  Expect 'worktree-record-main-status' (Status $main) "current`n"
  Expect 'worktree-record-worktree-status' (Status $wt) "current`n"
  Remove-Item -LiteralPath (Join-Path $mainReal '.milestone-config/.runtime/process-check.json')
  Expect 'main-record' (Record $main 'clean') ''
  Check 'main-marker-at-root' (Test-Path -LiteralPath (Join-Path $mainReal '.milestone-config/.runtime/process-check.json') -PathType Leaf)
  Expect 'main-record-worktree-status' (Status $wt) "current`n"
  $mainDeclined = Join-Path $mainReal '.milestone-config/.runtime/process-check-declined.json'
  [System.IO.File]::WriteAllText($mainDeclined, '{"declined":[]}', $utf8)
  Expect 'worktree-declined-file-due' (Status $wt) "due`n"
  Expect 'worktree-declined-record-main' (Record $main 'declined') ''
  Expect 'worktree-declined-current' (Status $wt) "current`n"
  Check 'worktree-no-own-declined' (-not (Test-Path -LiteralPath (Join-Path $wt '.milestone-config/.runtime/process-check-declined.json')))
  # a repo whose git dir is separate (--separate-git-dir, as a submodule has) keeps its marker under its own work tree, not beside the git dir
  $sepBase = New-Ws
  $sepWork = Join-Path $sepBase 'work'; $sepGit = Join-Path $sepBase 'gitdir'
  New-Item -ItemType Directory -Force -Path $sepWork | Out-Null
  $sepInit = & $git $sepBase @('init', '-q', '--separate-git-dir', $sepGit, $sepWork)
  Check 'separate-git-dir-init' ($sepInit.rc -eq 0) "err=[$($sepInit.err)]"
  Put $sepWork 'CLAUDE.md' "sep`n"
  $sepReal = (& $git $sepWork @('rev-parse', '--show-toplevel')).out.Trim()
  Expect 'separate-git-dir-record' (Record $sepWork 'clean') ''
  Check 'separate-git-dir-marker-under-work-tree' (Test-Path -LiteralPath (Join-Path $sepReal '.milestone-config/.runtime/process-check.json') -PathType Leaf)
  Check 'separate-git-dir-no-marker-beside-git-dir' (-not (Test-Path -LiteralPath (Join-Path $sepBase '.milestone-config')))
  Expect 'separate-git-dir-status' (Status $sepWork) "current`n"
  # a root outside any repository keeps its own marker
  $plain = New-Ws; Put $plain 'CLAUDE.md' "a`n"
  Expect 'plain-record' (Record $plain 'clean') ''
  Check 'plain-marker-at-root' ($null -ne (Marker-Text $plain))

  # ---- unusable markers read as due ----------------------------------------
  $ws = New-Ws; Put $ws 'CLAUDE.md' "a`n"
  Record $ws 'clean' | Out-Null
  foreach ($bad in @('not json', '{"hash":5}', '{"hash":null}', '[]', '{}', '{"outcome":"clean"}', '[{"hash":"x"}]', '"abc"', '', '{"hash":"x"} {"hash":"y"}')) {
    [System.IO.File]::WriteAllText((Marker-Path $ws), $bad, $utf8)
    Expect "bad-marker [$bad]" (Status $ws) "due`n"
  }
  # JSON whitespace only: a leading no-break space makes the marker unusable even with the right hash, as jq reads it
  Record $ws 'clean' | Out-Null
  $mt = Marker-Text $ws
  [System.IO.File]::WriteAllText((Marker-Path $ws), "$([char]0xA0)$mt", $utf8)
  Expect 'marker-leading-nbsp' (Status $ws) "due`n"
  [System.IO.File]::WriteAllText((Marker-Path $ws), " $mt", $utf8)
  Expect 'marker-leading-space-ok' (Status $ws) "current`n"
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
  Put $ws '.milestone-config/driver.json' "$([char]0xA0){}"
  Expect 'profile-leading-nbsp' (Status $ws) '' 1 'process-check: cannot read .milestone-config/driver.json'
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
  Expect 'usage-status-old-granularity-argument' (Run @('--status', $ws, 'issue')) '' 2 $USAGE
  Expect 'usage-record-no-outcome' (Run @('--record')) '' 2 $USAGE
  Expect 'usage-record-no-root' (Run @('--record', 'clean')) '' 2 $USAGE
  Expect 'usage-record-extra' (Run @('--record', 'clean', $ws, 'x')) '' 2 $USAGE
  Expect 'usage-record-old-granularity-argument' (Run @('--record', 'clean', $ws, 'milestone')) '' 2 $USAGE
  Expect 'usage-bad-outcome' (Run @('--record', 'maybe', $ws)) '' 2 $USAGE
  Expect 'usage-record-updated-refused' (Run @('--record', 'updated', $ws)) '' 2 $USAGE
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
