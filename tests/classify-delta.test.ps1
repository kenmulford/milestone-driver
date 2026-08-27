#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for classify-delta.ps1 (issues #476,
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'classify-delta.ps1'
$cases = Join-Path $here 'classify-delta.cases.tsv'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }

$pass = 0; $fail = 0; $skipped = 0
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cd-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$errFile = Join-Path $tmp 'err'

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Fixture([string]$path, [string]$content) {
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}
function Unescape([string]$s) { return $s -replace '\\n', "`n" }

function New-Repo([string]$d) {
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  & git -C $d init -q 2>$null | Out-Null
  & git -C $d config core.hooksPath (Join-Path $d '.git/no-such-hooks') 2>$null | Out-Null
  & git -C $d config commit.gpgsign false 2>$null | Out-Null
  & git -C $d config core.autocrlf false 2>$null | Out-Null
  & git -C $d config core.safecrlf false 2>$null | Out-Null
  & git -C $d config core.filemode false 2>$null | Out-Null
  & git -C $d config user.email 'tests@milestone-driver.invalid' 2>$null | Out-Null
  & git -C $d config user.name 'classify-delta tests' 2>$null | Out-Null
}
function Commit-All([string]$d, [string]$msg) {
  & git -C $d add -A 2>$null | Out-Null
  & git -C $d commit -q -m $msg 2>$null | Out-Null
}

function Invoke-Op([string]$repo, [string]$op) {
  if ($op -ceq '-') { return }
  if ($op.StartsWith('mv:', [StringComparison]::Ordinal)) {
    $rest = $op.Substring(3)
    $i = $rest.IndexOf(':', [StringComparison]::Ordinal)
    $from = $rest.Substring(0, $i)
    $to = $rest.Substring($i + 1)
    & git -C $repo mv $from $to 2>$null | Out-Null
  } elseif ($op.StartsWith('chmodx:', [StringComparison]::Ordinal)) {
    $target = $op.Substring(7)
    & git -C $repo update-index --chmod=+x $target 2>$null | Out-Null
  } else {
    Write-Error "FATAL: unknown op [$op]"
    exit 1
  }
}

function Get-Snapshot([string]$repo) {
  $t = (& pwsh -NoProfile -File $script '--snapshot' $repo 2>$null)
  return ("$t") -replace '\r?\n$', ''
}

function Invoke-Case([string]$name, [string]$repo, [string]$pre, [string]$wantOut, [string]$wantErr) {
  if ($pre -ceq '@NONE@') {
    $out = (& pwsh -NoProfile -File $script $repo 2> $errFile)
  } else {
    $out = (& pwsh -NoProfile -File $script $repo $pre 2> $errFile)
  }
  $rc = $LASTEXITCODE
  $out = ("$out") -replace '\r?\n$', ''
  $err = (Get-Content $errFile -Raw)
  $err = if ($null -eq $err) { '' } else { $err -replace '\r?\n$', '' }
  if ($rc -eq 0 -and $out -ceq $wantOut -and $err -ceq $wantErr) {
    $script:pass++
  } else {
    $script:fail++
    Write-Host ("FAIL {0,-38} rc={1} got[out={2} err={3}] want[out={4} err={5}]" -f $name, $rc, $out, $err, $wantOut, $wantErr)
  }
}

$expectCols = 8
$caseCount = 0
foreach ($row in (Get-Content $cases)) {
  if ($row -match '^\s*#' -or $row.Trim() -eq '') { continue }
  $r = $row -replace "`r$", ''
  $cols = $r -split "`t"
  if ($cols.Count -ne $expectCols) {
    Write-Error "FATAL: row failed to parse (got $($cols.Count) fields, want $expectCols): [$r]"
    exit 1
  }
  $caseCount++
  $name = $cols[0]; $path = $cols[1]; $base = $cols[2]; $work = $cols[3]
  $untracked = $cols[4]; $ops = $cols[5]; $wantOut = $cols[6]; $wantErr = $cols[7]

  $paths = $path -split '\|'
  $bases = $base -split '\|'
  $works = $work -split '\|'
  if ($bases.Count -ne $paths.Count -or $works.Count -ne $paths.Count) {
    Write-Error "FATAL: $name has $($paths.Count) paths but $($bases.Count) base / $($works.Count) work values"
    exit 1
  }

  $repo = Join-Path $tmp "r$caseCount"
  New-Repo $repo
  for ($i = 0; $i -lt $paths.Count; $i++) {
    Write-Fixture (Join-Path $repo $paths[$i]) (Unescape $bases[$i])
  }
  Commit-All $repo 'base'
  $pre = Get-Snapshot $repo
  for ($i = 0; $i -lt $paths.Count; $i++) {
    if ($works[$i] -ceq '=') {
    } elseif ($works[$i] -ceq '@DEL@') {
      Remove-Item (Join-Path $repo $paths[$i]) -Force
    } else {
      Write-Fixture (Join-Path $repo $paths[$i]) (Unescape $works[$i])
    }
  }
  if ($untracked -cne '-') { Write-Fixture (Join-Path $repo $untracked) "# untracked`n" }
  Invoke-Op $repo $ops

  Invoke-Case $name $repo $pre $wantOut $wantErr
}

if ($caseCount -eq 0) {
  Write-Error "FATAL: parsed 0 cases from $cases - this run tested nothing"
  exit 1
}

# ---- bespoke: THE case this classifier exists for (#625). The issue diff is
$b0 = Join-Path $tmp 'b-uncommitted-issue'; New-Repo $b0
Write-Fixture (Join-Path $b0 'a.sh') "exit 0`n"; Commit-All $b0 'base'
Write-Fixture (Join-Path $b0 'a.sh') "exit 1`n"
$pre0 = Get-Snapshot $b0
Write-Fixture (Join-Path $b0 'a.sh') "exit 1`n# note`n"
Invoke-Case 'uncommitted_issue_diff_then_comment_fix' $b0 $pre0 'comment-only' ''

# ---- bespoke: the same tree, classified against HEAD's tree instead. The
$b0b = Join-Path $tmp 'b-snapshot-at-head'; New-Repo $b0b
Write-Fixture (Join-Path $b0b 'a.sh') "exit 0`n"; Commit-All $b0b 'base'
Write-Fixture (Join-Path $b0b 'a.sh') "exit 1`n"
$pre0b = (& git -C $b0b rev-parse 'HEAD^{tree}' 2>$null)
Write-Fixture (Join-Path $b0b 'a.sh') "exit 1`n# note`n"
Invoke-Case 'snapshot_at_head_sees_issue_diff' $b0b $pre0b 'code-changed' 'code:a.sh'

# ---- bespoke: the pre-tree argument itself. A caller that forgot it, one that
$b8 = Join-Path $tmp 'b-no-pre'; New-Repo $b8
Write-Fixture (Join-Path $b8 'a.sh') "# c`n"; Commit-All $b8 'base'
Invoke-Case 'missing_pre' $b8 '@NONE@' 'code-changed' 'no-pre'

$b9 = Join-Path $tmp 'b-garbage-pre'; New-Repo $b9
Write-Fixture (Join-Path $b9 'a.sh') "# c`n"; Commit-All $b9 'base'
Invoke-Case 'garbage_pre' $b9 'deadbeef' 'code-changed' 'bad-pre:deadbeef'

$b10 = Join-Path $tmp 'b-blob-pre'; New-Repo $b10
Write-Fixture (Join-Path $b10 'a.sh') "# c`n"; Commit-All $b10 'base'
$blob = (& git -C $b10 hash-object -w a.sh 2>$null)
Invoke-Case 'blob_pre_is_not_a_tree' $b10 $blob 'code-changed' "bad-pre:$blob"

# ---- bespoke: a new file, staged or not. The delta is a tree pair now, so a
$b1 = Join-Path $tmp 'b-staged-new'; New-Repo $b1
Write-Fixture (Join-Path $b1 'a.sh') "# base`n"; Commit-All $b1 'base'
$pre1 = Get-Snapshot $b1
Write-Fixture (Join-Path $b1 'new.sh') "# a new note`n"
& git -C $b1 add new.sh 2>$null | Out-Null
Invoke-Case 'staged_new_file_all_comment' $b1 $pre1 'code-changed' 'added:new.sh'

# ---- bespoke: a staged comment edit. The snapshot reads the working tree
$b3 = Join-Path $tmp 'b-staged-edit'; New-Repo $b3
Write-Fixture (Join-Path $b3 'a.sh') "# old`nexit 0`n"; Commit-All $b3 'base'
$pre3 = Get-Snapshot $b3
Write-Fixture (Join-Path $b3 'a.sh') "# new`nexit 0`n"
& git -C $b3 add a.sh 2>$null | Out-Null
Invoke-Case 'staged_comment_edit' $b3 $pre3 'comment-only' ''

# ---- bespoke: a rename with no content change. `similarity index` /
$b4 = Join-Path $tmp 'b-rename'; New-Repo $b4
Write-Fixture (Join-Path $b4 'a.sh') "# one`n# two`n"; Commit-All $b4 'base'
$pre4 = Get-Snapshot $b4
& git -C $b4 mv a.sh b.sh 2>$null | Out-Null
Invoke-Case 'rename_only' $b4 $pre4 'code-changed' 'no-content:a.sh'

# ---- bespoke: a binary change. Git emits "Binary files ... differ" with no
$b5 = Join-Path $tmp 'b-binary'; New-Repo $b5
Write-Fixture (Join-Path $b5 'a.md') "<!-- c -->`n"; Commit-All $b5 'base'
$pre5 = Get-Snapshot $b5
[System.IO.File]::WriteAllBytes((Join-Path $b5 'a.md'), [byte[]](0x61, 0x00, 0x62, 0x00, 0x63))
Invoke-Case 'binary_change' $b5 $pre5 'code-changed' 'binary'

# ---- bespoke: "\ No newline at end of file" is a header, not a content line.
$b6 = Join-Path $tmp 'b-nonl'; New-Repo $b6
Write-Fixture (Join-Path $b6 'a.sh') "exit 0`n# old`n"; Commit-All $b6 'base'
$pre6 = Get-Snapshot $b6
Write-Fixture (Join-Path $b6 'a.sh') "exit 0`n# new"
Invoke-Case 'no_newline_at_eof' $b6 $pre6 'comment-only' ''

# ---- bespoke: a root that is not a git repo at all. Fail safe, never crash.
$emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
$b7 = Join-Path $tmp 'b-notrepo'; New-Item -ItemType Directory -Path $b7 -Force | Out-Null
Invoke-Case 'not_a_git_repo' $b7 $emptyTree 'code-changed' "bad-pre:$emptyTree"

# ---- bespoke: a TRACKED file that .gitignore also names. `git add -A` into an
$b15 = Join-Path $tmp 'b-tracked-ignored'; New-Repo $b15
Write-Fixture (Join-Path $b15 'gen.sh') "exit 0`n"
Write-Fixture (Join-Path $b15 'a.sh') "# old`n"
Write-Fixture (Join-Path $b15 '.gitignore') "gen.sh`n"
& git -C $b15 add -A 2>$null | Out-Null
& git -C $b15 add -f gen.sh 2>$null | Out-Null
& git -C $b15 commit -q -m 'base' 2>$null | Out-Null
$pre15 = Get-Snapshot $b15
Write-Fixture (Join-Path $b15 'gen.sh') "exit 99`n"
Write-Fixture (Join-Path $b15 'a.sh') "# new`n"
Invoke-Case 'tracked_ignored_file_code_change' $b15 $pre15 'code-changed' 'code:gen.sh'

# ---- bespoke: the control, and the other half of the rule. An UNTRACKED
$b16 = Join-Path $tmp 'b-untracked-ignored'; New-Repo $b16
Write-Fixture (Join-Path $b16 'a.sh') "# old`n"
Write-Fixture (Join-Path $b16 '.gitignore') "junk.log`n"
Commit-All $b16 'base'
Write-Fixture (Join-Path $b16 'junk.log') "noise`n"
$pre16 = Get-Snapshot $b16
Write-Fixture (Join-Path $b16 'a.sh') "# new`n"
Write-Fixture (Join-Path $b16 'junk.log') "noise`nmore noise`n"
Invoke-Case 'untracked_ignored_file_is_not_in_the_delta' $b16 $pre16 'comment-only' ''

# ---- bespoke: the same tracked-and-ignored change inside a LINKED worktree,
$b17 = Join-Path $tmp 'b-worktree'; New-Repo $b17
Write-Fixture (Join-Path $b17 'gen.sh') "exit 0`n"
Write-Fixture (Join-Path $b17 'a.sh') "# old`n"
Write-Fixture (Join-Path $b17 '.gitignore') "gen.sh`n"
& git -C $b17 add -A 2>$null | Out-Null
& git -C $b17 add -f gen.sh 2>$null | Out-Null
& git -C $b17 commit -q -m 'base' 2>$null | Out-Null
$wt17 = Join-Path $tmp 'b-worktree-linked'
& git -C $b17 worktree add -q $wt17 -b wtb 2>$null | Out-Null
$pre17 = Get-Snapshot $wt17
Write-Fixture (Join-Path $wt17 'gen.sh') "exit 99`n"
Write-Fixture (Join-Path $wt17 'a.sh') "# new`n"
Invoke-Case 'tracked_ignored_in_linked_worktree' $wt17 $pre17 'code-changed' 'code:gen.sh'

# ---- bespoke: the classify-mode no-delta branch, which needs a root whose
$b18 = Join-Path $tmp 'b-bare-src'; New-Repo $b18
Write-Fixture (Join-Path $b18 'a.sh') "# c`n"; Commit-All $b18 'base'
$tree18 = (& git -C $b18 rev-parse 'HEAD^{tree}' 2>$null)
$bare18 = Join-Path $tmp 'b-bare.git'
& git clone -q --bare $b18 $bare18 2>$null | Out-Null
Invoke-Case 'bare_repo_post_snapshot_fails' $bare18 $tree18 'code-changed' 'no-delta'

# ---- bespoke: a same-size edit that every stat field calls clean. This is
$racyStamp = [datetime]::SpecifyKind([datetime]::Parse('2020-01-02T03:04:05'), [System.DateTimeKind]::Utc)
$b19 = Join-Path $tmp 'b-racy'; New-Repo $b19
& git -C $b19 config core.trustctime false 2>$null | Out-Null
& git -C $b19 config core.checkStat minimal 2>$null | Out-Null
Write-Fixture (Join-Path $b19 'a.sh') "# c`nexit 0`n"
[System.IO.File]::SetLastWriteTimeUtc((Join-Path $b19 'a.sh'), $racyStamp)
Commit-All $b19 'base'
$pre19 = (& git -C $b19 rev-parse 'HEAD^{tree}' 2>$null)
Write-Fixture (Join-Path $b19 'a.sh') "# c`nexit 1`n"
[System.IO.File]::SetLastWriteTimeUtc((Join-Path $b19 'a.sh'), $racyStamp)
[System.IO.File]::SetLastWriteTimeUtc((Join-Path $b19 '.git/index'), $racyStamp)
Invoke-Case 'racily_clean_same_size_edit' $b19 $pre19 'code-changed' 'code:a.sh'

# ---- bespoke: --snapshot itself, the two properties the callers depend on.
$b13 = Join-Path $tmp 'b-snapshot-index'; New-Repo $b13
Write-Fixture (Join-Path $b13 'a.sh') "# base`n"; Commit-All $b13 'base'
Write-Fixture (Join-Path $b13 'a.sh') "# edited`n"
Write-Fixture (Join-Path $b13 'new.sh') "# untracked`n"
$before = (& git -C $b13 status --porcelain 2>$null) -join "`n"
$snapOut = Get-Snapshot $b13
$after = (& git -C $b13 status --porcelain 2>$null) -join "`n"
$snapType = (& git -C $b13 cat-file -t $snapOut 2>$null)
if ($snapType -ceq 'tree' -and $before -ceq $after) {
  $script:pass++
} else {
  $script:fail++
  Write-Host ("FAIL {0,-38} snapshot=[{1}] type=[{2}] before=[{3}] after=[{4}]" -f 'snapshot_leaves_index_untouched', $snapOut, $snapType, $before, $after)
}

$b14 = Join-Path $tmp 'b-snapshot-notrepo'; New-Item -ItemType Directory -Path $b14 -Force | Out-Null
$snapOut = (& pwsh -NoProfile -File $script '--snapshot' $b14 2> $errFile)
$snapRc = $LASTEXITCODE
$snapOut = ("$snapOut") -replace '\r?\n$', ''
$snapErr = (Get-Content $errFile -Raw)
$snapErr = if ($null -eq $snapErr) { '' } else { $snapErr -replace '\r?\n$', '' }
if ($snapRc -ne 0 -and $snapOut -ceq '' -and $snapErr -ceq 'snapshot-failed') {
  $script:pass++
} else {
  $script:fail++
  Write-Host ("FAIL {0,-38} rc={1} out=[{2}] err=[{3}]" -f 'snapshot_failure_is_loud', $snapRc, $snapOut, $snapErr)
}

# ---- bespoke: a real index that exists and cannot be read. The seed IS the
$b20 = Join-Path $tmp 'b-unreadable-seed'; New-Repo $b20
Write-Fixture (Join-Path $b20 'a.sh') "# c`n"; Commit-All $b20 'base'
$idx20 = Join-Path $b20 '.git/index'
$canDeny = -not $IsWindows
if ($canDeny) {
  & chmod 000 $idx20 2>$null | Out-Null
  try { [System.IO.File]::ReadAllBytes($idx20) | Out-Null; $canDeny = $false } catch { $canDeny = $true }
}
if (-not $canDeny) {
  $script:skipped++
  if (-not $IsWindows) { & chmod 600 $idx20 2>$null | Out-Null }
  Write-Host ("SKIP {0,-38} no way to make the real index unreadable here" -f 'unreadable_seed_is_loud')
} else {
  $snapRoot = [System.IO.Path]::GetTempPath()
  $beforeDirs = @(Get-ChildItem -Path $snapRoot -Filter 'cd-snap-*' -Directory -ErrorAction SilentlyContinue).Count
  $snapOut = (& pwsh -NoProfile -File $script '--snapshot' $b20 2> $errFile)
  $snapRc = $LASTEXITCODE
  $snapOut = ("$snapOut") -replace '\r?\n$', ''
  $snapErr = (Get-Content $errFile -Raw)
  $snapErr = if ($null -eq $snapErr) { '' } else { $snapErr -replace '\r?\n$', '' }
  & chmod 600 $idx20 2>$null | Out-Null
  $afterDirs = @(Get-ChildItem -Path $snapRoot -Filter 'cd-snap-*' -Directory -ErrorAction SilentlyContinue).Count
  if ($snapRc -ne 0 -and $snapOut -ceq '' -and $snapErr -ceq 'snapshot-failed' -and $beforeDirs -eq $afterDirs) {
    $script:pass++
  } else {
    $script:fail++
    Write-Host ("FAIL {0,-38} rc={1} out=[{2}] err=[{3}] tempdirs {4}->{5}" -f 'unreadable_seed_is_loud', $snapRc, $snapOut, $snapErr, $beforeDirs, $afterDirs)
  }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "classify-delta.ps1: $pass passed, $fail failed, $skipped skipped (parsed $caseCount TSV cases + 19 bespoke)"
if ($fail -ne 0) { exit 1 }
