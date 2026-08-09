#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for classify-delta.ps1 (issue #476).
# Behavior-identical pwsh sibling of tests/classify-delta.test.sh: same
# tests/classify-delta.cases.tsv table (including its `|`-separated multi-file
# rows and its git `ops` column), same seven bespoke cases after it.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'classify-delta.ps1'
$cases = Join-Path $here 'classify-delta.cases.tsv'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }

$pass = 0; $fail = 0
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cd-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$errFile = Join-Path $tmp 'err'

# Byte-exact writes: UTF-8 without a BOM and LF line endings, so the fixture
# content the classifier sees is identical to what the bash runner writes.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Fixture([string]$path, [string]$content) {
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}
function Unescape([string]$s) { return $s -replace '\\n', "`n" }

# New-Repo <dir> - a throwaway repo pinned against the developer's global git
# config: no hooks, no signing, no CRLF translation, fixed identity.
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

# The row's single git operation, run after `work` lands.
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

function Invoke-Case([string]$name, [string]$repo, [string]$wantOut, [string]$wantErr) {
  $out = (& pwsh -NoProfile -File $script $repo 2> $errFile)
  $rc = $LASTEXITCODE
  # Match the bash runner's $(...) capture, which strips only a trailing
  # newline - NOT a broad .Trim(), which would mask a whitespace divergence.
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
  # A row that does not parse into exactly $expectCols fields is a corrupt
  # fixture, not a silently-defaulted pass.
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
  for ($i = 0; $i -lt $paths.Count; $i++) {
    if ($works[$i] -ceq '=') {
      # untouched
    } elseif ($works[$i] -ceq '@DEL@') {
      Remove-Item (Join-Path $repo $paths[$i]) -Force
    } else {
      Write-Fixture (Join-Path $repo $paths[$i]) (Unescape $works[$i])
    }
  }
  if ($untracked -cne '-') { Write-Fixture (Join-Path $repo $untracked) "# untracked`n" }
  Invoke-Op $repo $ops

  Invoke-Case $name $repo $wantOut $wantErr
}

if ($caseCount -eq 0) {
  Write-Error "FATAL: parsed 0 cases from $cases - this run tested nothing"
  exit 1
}

# ---- bespoke: a STAGED new file is visible in `git diff HEAD` as a
# "new file mode" header, so it is classified on its content, not treated as
# untracked. This is the pair to untracked_only above: visibility is the rule.
$b1 = Join-Path $tmp 'b-staged-new'; New-Repo $b1
Write-Fixture (Join-Path $b1 'a.sh') "# base`n"; Commit-All $b1 'base'
Write-Fixture (Join-Path $b1 'new.sh') "# a new note`n"
& git -C $b1 add new.sh 2>$null | Out-Null
Invoke-Case 'staged_new_file_all_comment' $b1 'comment-only' ''

$b2 = Join-Path $tmp 'b-staged-new-code'; New-Repo $b2
Write-Fixture (Join-Path $b2 'a.sh') "# base`n"; Commit-All $b2 'base'
Write-Fixture (Join-Path $b2 'new.sh') "exit 1`n"
& git -C $b2 add new.sh 2>$null | Out-Null
Invoke-Case 'staged_new_file_with_code' $b2 'code-changed' 'code:new.sh'

# ---- bespoke: a staged comment edit. Bare `git diff -U0` prints nothing once
# the tree is staged (a denied commit at tests-green exit 2 leaves it that
# way); diffing against HEAD still sees it.
$b3 = Join-Path $tmp 'b-staged-edit'; New-Repo $b3
Write-Fixture (Join-Path $b3 'a.sh') "# old`nexit 0`n"; Commit-All $b3 'base'
Write-Fixture (Join-Path $b3 'a.sh') "# new`nexit 0`n"
& git -C $b3 add a.sh 2>$null | Out-Null
Invoke-Case 'staged_comment_edit' $b3 'comment-only' ''

# ---- bespoke: a rename with no content change. `similarity index` /
# `rename from` / `rename to` are skipped as headers, leaving zero content
# lines, and a path change is not a comment edit.
$b4 = Join-Path $tmp 'b-rename'; New-Repo $b4
Write-Fixture (Join-Path $b4 'a.sh') "# one`n# two`n"; Commit-All $b4 'base'
& git -C $b4 mv a.sh b.sh 2>$null | Out-Null
Invoke-Case 'rename_only' $b4 'code-changed' 'no-content:a.sh'

# ---- bespoke: a binary change. Git emits "Binary files ... differ" with no
# readable line, on a file whose extension IS mapped, so only the named header
# shape can catch it.
$b5 = Join-Path $tmp 'b-binary'; New-Repo $b5
Write-Fixture (Join-Path $b5 'a.md') "<!-- c -->`n"; Commit-All $b5 'base'
[System.IO.File]::WriteAllBytes((Join-Path $b5 'a.md'), [byte[]](0x61, 0x00, 0x62, 0x00, 0x63))
Invoke-Case 'binary_change' $b5 'code-changed' 'binary'

# ---- bespoke: "\ No newline at end of file" is a header, not a content line.
# Dropping the trailing newline off a reworded comment emits it.
$b6 = Join-Path $tmp 'b-nonl'; New-Repo $b6
Write-Fixture (Join-Path $b6 'a.sh') "exit 0`n# old`n"; Commit-All $b6 'base'
Write-Fixture (Join-Path $b6 'a.sh') "exit 0`n# new"
Invoke-Case 'no_newline_at_eof' $b6 'comment-only' ''

# ---- bespoke: a root that is not a git repo at all. Fail safe, never crash.
$b7 = Join-Path $tmp 'b-notrepo'; New-Item -ItemType Directory -Path $b7 -Force | Out-Null
Invoke-Case 'not_a_git_repo' $b7 'code-changed' 'no-delta'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "classify-delta.ps1: $pass passed, $fail failed (parsed $caseCount TSV cases + 7 bespoke)"
if ($fail -ne 0) { exit 1 }
