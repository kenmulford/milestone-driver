#!/usr/bin/env pwsh
# milestone-driver — golden-matrix runner for expand-domain-skills.ps1 (issue #589).
# Twin of tests/expand-domain-skills.test.sh: SAME cases table, SAME fixture
# tree, SAME comparison rule (trailing newlines stripped from both the actual
# and the expected stream), so a divergence between the two legs shows up as a
# failing row here rather than as a silent behavior split in the field.
# Column meanings and the `\n` escape convention are documented once, in the .sh
# runner's header.
#
# WHY ProcessStartInfo.ArgumentList and NOT `pwsh -File $script $root @argv`:
# PowerShell's NATIVE-command argument binder expands a wildcard argument
# against the current directory when it matches something, so a bare `*` entry
# reaches the child as the runner's own file names and the `bare_star` case can
# never be driven. ArgumentList hands each argument to the OS verbatim — no
# shell, no glob. The bash runner's `set -f` around its split is the same guard.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here '..' 'scripts' 'expand-domain-skills.ps1'
$cases = Join-Path $here 'expand-domain-skills.cases.tsv'
$fix = Join-Path $here 'fixtures' 'expand-domain-skills'
if (-not (Test-Path $script)) { Write-Error "FATAL: missing $script"; exit 3 }
if (-not (Test-Path $cases)) { Write-Error "FATAL: missing $cases"; exit 3 }
if (-not (Test-Path $fix)) { Write-Error "FATAL: missing $fix"; exit 3 }
$pass = 0; $fail = 0
# HOME faked to a PER-RUN TEMP COPY of the fixture, NEVER to $fix itself: each
# child pwsh writes its own .cache/powershell/ and .local/share/powershell/
# under $HOME, and aiming that at the tracked fixture tree left the worktree
# dirty after every run. Created AFTER the FATAL guards above so no early exit
# leaks it; removed below the loop. The wildcard source skips dot-prefixed
# entries (no -Force), matching the .sh runner's `"$FIX"/*` glob.
$tmpHome = Join-Path ([System.IO.Path]::GetTempPath()) ('eds-' + [System.Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tmpHome)
Copy-Item -Path (Join-Path $fix '*') -Destination $tmpHome -Recurse
# Strip EVERY trailing newline, matching the bash runner's `$(cat file)` — never
# a broad .Trim(), which would mask leading/internal-whitespace divergence.
function Strip-Trailing([string]$s) { if ($null -eq $s) { return '' } return ($s -replace '(\r?\n)+$', '') }
function Unesc([string]$s) { if ($null -eq $s) { return '' } return ($s -replace '\\n', "`n") }
foreach ($line in Get-Content $cases) {
  if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
  $f = $line -split "`t"
  $name = $f[0]
  $rootname = if ($f.Count -gt 1) { $f[1] } else { '' }
  $entries = if ($f.Count -gt 2) { $f[2] } else { '' }
  $rawOut = if ($f.Count -gt 3) { $f[3] } else { '' }
  $rawErr = if ($f.Count -gt 4) { $f[4] } else { '' }
  $expOut = Unesc $rawOut
  $expErr = Unesc $rawErr
  # Root sentinels, one-for-one with the .sh runner: __EMPTY__ is the empty
  # root, a `~/`-prefixed value rides through VERBATIM so the script's own tilde
  # resolution is what the row tests.
  $root = if ($rootname -ceq '__EMPTY__') { '' }
    elseif ($rootname.StartsWith('~/', [System.StringComparison]::Ordinal)) { $rootname }
    else { Join-Path $fix $rootname }
  $argv = @($entries -split ' ' | Where-Object { $_ -ne '' })
  $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
  foreach ($a in @('-NoProfile', '-File', $script, $root) + $argv) { [void]$psi.ArgumentList.Add($a) }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  # HOME faked to the temp COPY on EVERY row, so a `~/…` root is hermetic here
  # exactly as it is on the bash leg. UseShellExecute must be false before
  # .Environment is touched, and redirection requires it anyway.
  $psi.UseShellExecute = $false
  $psi.Environment['HOME'] = $tmpHome
  $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
  $p = [System.Diagnostics.Process]::Start($psi)
  # Both streams are read before WaitForExit — the outputs are single-line-scale,
  # well under a pipe buffer, so a sequential read cannot deadlock here.
  $out = Strip-Trailing $p.StandardOutput.ReadToEnd()
  $err = Strip-Trailing $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $rc = $p.ExitCode
  # Ordinal, never -ceq: PowerShell's string operators are InvariantCulture
  # compares under ICU, which treats an ignorable character as absent and would
  # score a byte-divergent stream as a pass — the one thing this matrix exists
  # to catch.
  $okOut = [System.StringComparer]::Ordinal.Compare($out, $expOut) -eq 0
  $okErr = [System.StringComparer]::Ordinal.Compare($err, $expErr) -eq 0
  if ($rc -eq 0 -and $okOut -and $okErr) { $pass++ }
  else {
    $fail++
    Write-Host "FAIL $name root[$rootname] entries[$entries] got[rc=$rc out=$out err=$err] want[rc=0 out=$expOut err=$expErr]"
  }
}
Remove-Item -LiteralPath $tmpHome -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "expand-domain-skills.ps1: $pass passed, $fail failed"
if ($fail -ne 0) { exit 1 }
