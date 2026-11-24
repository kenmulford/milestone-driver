#!/usr/bin/env pwsh
# milestone-driver - golden-matrix runner for the protected-branch gates, no-push
# and no-pr-to-protected (issue #813). One row per tests/protected-branch.cases.tsv
# line, run against the leg's script with a stubbed `gh`.
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here '_lib.ps1'); Set-Leg $Leg
$Root = (Resolve-Path (Join-Path $Here '..')).Path
$Cases = Join-Path $Here 'protected-branch.cases.tsv'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }

foreach ($v in 'NO_PUSH', 'TESTS_GREEN', 'CODE_REVIEW_GATE') { [Environment]::SetEnvironmentVariable("CLAUDE_HOOK_DISABLE_$v", $null) }

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$Tmp = (Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())) -replace '\\', '/'
New-Item -ItemType Directory -Path $Tmp | Out-Null

function New-Repo([string]$dir, [string]$branch) {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  git -C $dir init -q -b $branch
  git -C $dir -c user.email=pb@example.invalid -c user.name=pb commit -q --allow-empty -m init
  return $dir
}

# A gh stub that answers only `gh pr view [<pr>] [-R o/r] --json baseRefName`
# from map.txt (`<pr> <base>` per line, `*` for any PR), and the default-branch
# lookups `gh repo view [o/r] --json defaultBranchRef` and `gh api repos/o/r
# --jq .default_branch` from its `DEFAULT <branch>` line; needrepo makes it
# refuse a pr view without `-R o/r` and a repo view without `o/r`, so a gate
# that drops the repo goes red.
$StubSh = @'
#!/usr/bin/env bash
d="${BASH_SOURCE[0]%/*}"
default() { while read -r n b; do [ "$n" = DEFAULT ] && { echo "$b"; exit 0; }; done < "$d/map.txt"; exit 1; }
needrepo() { if [ -f "$d/needrepo" ]; then case " $* " in *" -R o/r "*) ;; *) exit 1 ;; esac; fi; }
if [ "$1" = repo ] && [ "$2" = view ]; then
  [ -f "$d/needrepo" ] && [ "$3" != o/r ] && exit 1
  case " $* " in *defaultBranchRef*) default ;; esac; exit 1
fi
if [ "$1" = api ] && [ "$2" = repos/o/r ]; then
  case " $* " in *.default_branch*) default ;; esac; exit 1
fi
[ "$1" = pr ] && [ "$2" = view ] || exit 1
num="$3"; case "$num" in -*) num='*' ;; esac
needrepo "$@"
while read -r n b; do
  if [ "$n" = "$num" ] || [ "$n" = '*' ]; then echo "{\"baseRefName\":\"$b\"}"; exit 0; fi
done < "$d/map.txt"
exit 1
'@
$StubPs1 = @'
$d = $PSScriptRoot
$all = " $($args -join ' ') "
function Default { foreach ($l in (Get-Content "$d/map.txt")) { $n, $b = $l -split ' ', 2; if ($n -eq 'DEFAULT') { Write-Output $b; exit 0 } }; exit 1 }
$needRepo = (Test-Path "$d/needrepo") -and ($all -notlike '* -R o/r *')
if ($args.Count -ge 2 -and $args[0] -eq 'repo' -and $args[1] -eq 'view') { if (((-not (Test-Path "$d/needrepo")) -or $args[2] -eq 'o/r') -and $all -like '*defaultBranchRef*') { Default }; exit 1 }
if ($args.Count -ge 2 -and $args[0] -eq 'api' -and $args[1] -eq 'repos/o/r') { if ($all -like '*.default_branch*') { Default }; exit 1 }
if ($args.Count -lt 2 -or $args[0] -ne 'pr' -or $args[1] -ne 'view') { exit 1 }
$num = if ($args.Count -ge 3 -and -not ([string]$args[2]).StartsWith('-')) { [string]$args[2] } else { '*' }
if ($needRepo) { exit 1 }
foreach ($l in (Get-Content "$d/map.txt")) {
  $n, $b = $l -split ' ', 2
  if ($n -eq $num -or $n -eq '*') { Write-Output "{`"baseRefName`":`"$b`"}"; exit 0 }
}
exit 1
'@

function New-GhStub([string]$spec) {
  $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'gh'), $StubSh.Replace("`r`n", "`n") + "`n", $utf8)
  & chmod +x (Join-Path $dir 'gh')
  [System.IO.File]::WriteAllText((Join-Path $dir 'gh.ps1'), $StubPs1 + "`n", $utf8)
  if ($spec.StartsWith('R!')) { $spec = $spec.Substring(2); [System.IO.File]::WriteAllText((Join-Path $dir 'needrepo'), 'o/r', $utf8) }
  $lines = @()
  if ($spec -ne 'FAIL') { foreach ($e in ($spec -split ',')) { $k, $v = $e -split '=', 2; $lines += "$k $v" } }
  [System.IO.File]::WriteAllText((Join-Path $dir 'map.txt'), (($lines -join "`n") + "`n"), $utf8)
  return $dir
}

$MainRepo = New-Repo "$Tmp/main-repo" 'main'
$DevRepo = New-Repo "$Tmp/dev-repo" 'develop'
$CfgRepo = New-Repo "$Tmp/cfg-repo" 'develop'
git -C $CfgRepo config --add remote.origin.push refs/heads/develop:refs/heads/main
$FeatRepo = New-Repo "$Tmp/feat-repo" 'issue/9-x'
git -C $FeatRepo branch main
$Ws = @{}; $Integration = @{ P = 'develop'; EXTRA = 'develop'; STAGING = 'staging'; NOPROFILE = 'develop'; NODEV = 'dev'; NOINTEG = 'dev' }
function New-Ws([string]$name, [string]$profileJson, [bool]$originDevelop) {
  $d = New-Repo "$Tmp/ws-$name" 'issue/9-x'
  if ($profileJson) {
    New-Item -ItemType Directory -Path "$d/.milestone-config" | Out-Null
    [System.IO.File]::WriteAllText("$d/.milestone-config/driver.json", $profileJson, $utf8)
  }
  if ($originDevelop) { git -C $d update-ref refs/remotes/origin/develop HEAD }
  $script:Ws[$name] = $d
}
New-Ws 'P' '{"protectedBranch":"main","integrationBranch":"develop"}' $false
New-Ws 'EXTRA' '{"protectedBranch":"main","integrationBranch":"develop","protectedBranches":["live","rel-*"]}' $false
New-Ws 'STAGING' '{"protectedBranch":"main","integrationBranch":"staging"}' $false
New-Ws 'NOPROFILE' '' $true
New-Ws 'NODEV' '' $false
New-Ws 'NOINTEG' '{"protectedBranch":"main"}' $false

foreach ($row in Get-Content $Cases) {
  if ($row -eq '' -or $row.StartsWith('#')) { continue }
  $c = $row -split "`t"
  $name = $c[0]; $gate = $c[1]; $tool = $c[2]; $wsn = if ($c[3]) { $c[3] } else { 'P' }
  $gh = $c[4]; $want = $c[5]
  $in = $c[6].Replace('__MAIN__', $MainRepo).Replace('__DEV__', $DevRepo).Replace('__CFG__', $CfgRepo).Replace('__FEAT__', $FeatRepo).Replace('\n', "`n")
  $cwd = $Ws[$wsn]
  if ($tool) { $payload = @{ tool_name = $tool; tool_input = ($in | ConvertFrom-Json -AsHashtable); cwd = $cwd } }
  else { $payload = @{ tool_name = 'Bash'; tool_input = @{ command = $in }; cwd = $cwd } }
  $json = $payload | ConvertTo-Json -Depth 6 -Compress

  $origPath = $env:PATH; $stub = $null
  if ($gh) { $stub = New-GhStub $gh; $env:PATH = "$stub$([System.IO.Path]::PathSeparator)$origPath" }
  $r = Invoke-Leg -Script (Join-Path $Root 'hooks' $gate) -Stdin $json -Cwd $cwd
  $env:PATH = $origPath
  if ($stub) { Remove-Item -Recurse -Force $stub -ErrorAction SilentlyContinue }

  $err = $r.err.TrimEnd("`r", "`n")
  if ($want -eq 'allow') { $wantRc = 0; $wantErr = '' }
  else {
    $p = $want -split '\|'
    $wantRc = 2
    $wantErr = "milestone-driver: $($p[1]) into '$($p[2])' is blocked. Agents stop at the integration branch '$($Integration[$wsn])'; anything past it is a human step."
  }
  if ($r.rc -eq $wantRc -and $err -eq $wantErr -and $r.out -eq '') { $pass++ }
  else {
    $fail++
    Write-Error "FAIL $name`: rc=$($r.rc) (want $wantRc) stderr=[$err] (want [$wantErr]) stdout=[$($r.out)]" -ErrorAction Continue
  }
}

# ---- bespoke: the override env var still opens both gates
foreach ($g in 'no-push', 'no-pr-to-protected') {
  $cmd = if ($g -eq 'no-push') { 'git push origin main' } else { 'gh pr create --base main --title x' }
  $json = @{ tool_name = 'Bash'; tool_input = @{ command = $cmd }; cwd = $Ws['P'] } | ConvertTo-Json -Compress
  $r = Invoke-Leg -Script (Join-Path $Root 'hooks' $g) -Stdin $json -Cwd $Ws['P'] -Env @{ CLAUDE_HOOK_DISABLE_NO_PUSH = '1' }
  if ($r.rc -eq 0 -and $r.err -eq '' -and $r.out -eq '') { $pass++ }
  else { $fail++; Write-Error "FAIL override_$g`: rc=$($r.rc) stderr=[$($r.err)]" -ErrorAction Continue }
}

# ---- bespoke, sh leg: with jq absent the MCP path cannot read a base, so it denies;
# the Bash path keeps develop's jq fail-open.
if ($Leg -eq 'sh') {
  $NoJq = "$Tmp/nojq-bin"
  New-Item -ItemType Directory -Path $NoJq | Out-Null
  foreach ($t in 'git', 'sed', 'head', 'tr', 'cat', 'grep') { Add-ToolStub $t $NoJq }
  $rows = @(
    @('nojq_mcp_merge', 'mcp__plugin_github_github__merge_pull_request', @{ owner = 'o'; repo = 'r'; pullNumber = 5 }, 'merging a PR', 'unknown base'),
    @('nojq_mcp_create', 'mcp__plugin_github_github__create_pull_request', @{ owner = 'o'; repo = 'r'; head = 'x'; base = 'develop' }, 'opening a PR', 'unknown base'),
    @('nojq_mcp_update_base', 'mcp__plugin_github_github__update_pull_request', @{ owner = 'o'; repo = 'r'; pullNumber = 5; base = 'develop' }, 'retargeting a PR', 'unknown base'),
    @('nojq_mcp_update_title', 'mcp__plugin_github_github__update_pull_request', @{ owner = 'o'; repo = 'r'; pullNumber = 5; title = 't' }, '', ''),
    @('nojq_mcp_push_files', 'mcp__plugin_github_github__push_files', @{ owner = 'o'; repo = 'r'; branch = 'issue/9-x'; files = @(); message = 'm' }, 'pushing', 'unknown branch'),
    @('nojq_mcp_file_write', 'mcp__plugin_github_github__create_or_update_file', @{ owner = 'o'; repo = 'r'; path = 'a'; branch = 'issue/9-x'; message = 'm'; content = 'x' }, 'pushing', 'unknown branch'),
    @('nojq_bash_create_base', 'Bash', @{ command = 'gh pr create --base main --title x' }, '', '')
  )
  foreach ($c in $rows) {
    $json = @{ tool_name = $c[1]; tool_input = $c[2]; cwd = $Ws['P'] } | ConvertTo-Json -Depth 6 -Compress
    $r = Invoke-Leg -Script (Join-Path $Root 'hooks' 'no-pr-to-protected') -Stdin $json -Cwd $Ws['P'] -Env @{ PATH = $NoJq }
    $err = $r.err.TrimEnd("`r", "`n")
    if ($c[3]) { $wantRc = 2; $wantErr = "milestone-driver: $($c[3]) into '$($c[4])' is blocked. Agents stop at the integration branch 'develop'; anything past it is a human step." }
    else { $wantRc = 0; $wantErr = '' }
    if ($r.rc -eq $wantRc -and $err -eq $wantErr -and $r.out -eq '') { $pass++ }
    else { $fail++; Write-Error "FAIL $($c[0]): rc=$($r.rc) (want $wantRc) stderr=[$err] (want [$wantErr])" -ErrorAction Continue }
  }
}

Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "protected-branch ($Leg): $pass passed, $fail failed"
if ($fail -eq 0) { exit 0 } else { exit 1 }
