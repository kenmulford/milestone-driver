#!/usr/bin/env pwsh
# milestone-driver - agent-gate suite (issue #813): hooks/agent-env, shims/gh,
# shims/git and git-hooks/*. git cases run real temp repos against a local bare
# remote with the GIT_CONFIG_* entries agent-env writes; shim cases run the shims
# under bash with a stub `gh` or the real git behind them; agent-env cases source
# the written env file in bash.
param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Here '_lib.ps1'); Set-Leg $Leg
$Root = ((Resolve-Path (Join-Path $Here '..')).Path) -replace '\\', '/'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Error 'FATAL: git required'; exit 3 }
$Bash = Get-BashBin

foreach ($v in 'NO_PUSH', 'TESTS_GREEN', 'CODE_REVIEW_GATE') { [Environment]::SetEnvironmentVariable("CLAUDE_HOOK_DISABLE_$v", $null) }

$utf8 = [System.Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
$Tmp = (Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())) -replace '\\', '/'
New-Item -ItemType Directory -Path $Tmp | Out-Null

function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:pass++ }
  else { $script:fail++; Write-Error "FAIL $name`: $detail" -ErrorAction Continue }
}

function Write-File([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, $text.Replace("`r`n", "`n"), $utf8)
}

$Sep = [System.IO.Path]::PathSeparator
function Deny([string]$action, [string]$branch, [string]$integ = 'develop') {
  return "milestone-driver: $action into '$branch' is blocked. Agents stop at the integration branch '$integ'; anything past it is a human step."
}

# Inside an agent session this runner inherits the installed plugin's shims/ on
# PATH and its GIT_CONFIG_* entries; every git child here gets a PATH without any
# shims/ directory, the real git by absolute path, and this suite's own GIT_CONFIG_*.
$CleanPath = (($env:PATH -split [regex]::Escape($Sep)) | Where-Object { $_ -and -not (Test-Path -LiteralPath (Join-Path $_ '_protected.sh')) }) -join $Sep
$GitBin = $null
foreach ($d in ($CleanPath -split [regex]::Escape($Sep))) {
  foreach ($n in 'git', 'git.exe') { if (-not $GitBin -and (Test-Path -LiteralPath (Join-Path $d $n) -PathType Leaf)) { $GitBin = (Join-Path $d $n) -replace '\\', '/' } }
}
$EmptyGlobal = "$Tmp/empty.gitconfig"
Write-File $EmptyGlobal ''
$GitEnv = @{ GIT_CONFIG_COUNT = '1'; GIT_CONFIG_KEY_0 = 'core.hooksPath'; GIT_CONFIG_VALUE_0 = "$Root/git-hooks"; GIT_CONFIG_GLOBAL = $EmptyGlobal; GIT_CONFIG_NOSYSTEM = '1'; PATH = $CleanPath }
function Get-GitEnv([hashtable]$extra = @{}) {
  $e = @{}; foreach ($k in $GitEnv.Keys) { $e[$k] = $GitEnv[$k] }
  foreach ($k in $extra.Keys) { $e[$k] = $extra[$k] }
  return $e
}

# ---- git: hooks/agent-env's GIT_CONFIG_* against real repos -----------------
function Invoke-Git([string]$dir, [string[]]$a, [hashtable]$extra = @{}) {
  return Invoke-Child -Exe $GitBin -Argv (@('-C', $dir, '-c', 'user.email=ag@example.invalid', '-c', 'user.name=ag') + $a) -Stdin '' -Cwd $dir -Env (Get-GitEnv $extra)
}

$Remote = "$Tmp/remote.git"
git init -q --bare $Remote
function New-Work([string]$name) {
  $d = "$Tmp/$name"
  New-Item -ItemType Directory -Path $d | Out-Null
  git -C $d init -q -b feat
  git -C $d -c user.email=ag@example.invalid -c user.name=ag commit -q --allow-empty -m init
  git -C $d branch main
  git -C $d remote add origin $Remote
  Write-File "$d/.milestone-config/driver.json" '{"protectedBranch":"main","integrationBranch":"develop"}'
  return $d
}
function Remote-Has([string]$b) { git -C $Remote rev-parse --verify --quiet "refs/heads/$b" *> $null; return ($LASTEXITCODE -eq 0) }

function Test-PushDeny([string]$name, [string[]]$push, [string]$branch, [scriptblock]$setup = $null) {
  $d = New-Work $name
  if ($setup) { & $setup $d }
  $r = Invoke-Git $d (@('push') + $push)
  Check $name ($r.rc -ne 0 -and $r.err.Contains((Deny 'pushing' $branch))) "rc=$($r.rc) stderr=[$($r.err.Trim())]"
}
Test-PushDeny 'push_main_denies' @('origin', 'main') 'main'
Test-PushDeny 'push_release_denies' @('origin', 'feat:release/1.2') 'release/1.2'
Test-PushDeny 'push_all_local_main_denies' @('--all', 'origin') 'main'
Test-PushDeny 'push_glob_refspec_denies' @('origin', 'refs/heads/*:refs/heads/*') 'main'
Test-PushDeny 'push_default_upstream_main_denies' @() 'main' {
  param($d)
  git -C $d config push.default upstream
  git -C $d config branch.feat.remote origin
  git -C $d config branch.feat.merge refs/heads/main
}
Check 'push_denied_refs_absent' (-not (Remote-Has 'main') -and -not (Remote-Has 'release/1.2')) 'a denied push reached the remote'

$d = New-Work 'push_feature'
$r = Invoke-Git $d @('push', 'origin', 'feat')
Check 'push_feature_allows' ($r.rc -eq 0 -and (Remote-Has 'feat')) "rc=$($r.rc) stderr=[$($r.err.Trim())]"
$r = Invoke-Git $d @('push', 'origin', 'feat:milestone-54-x')
Check 'push_milestone_branch_allows' ($r.rc -eq 0 -and (Remote-Has 'milestone-54-x')) "rc=$($r.rc) stderr=[$($r.err.Trim())]"
$r = Invoke-Git $d @('push', 'origin', ':feat')
Check 'delete_feature_allows' ($r.rc -eq 0 -and -not (Remote-Has 'feat')) "rc=$($r.rc) stderr=[$($r.err.Trim())]"

# ---- git: the repo's own hooks still run ------------------------------------
$d = New-Work 'repo_prepush'
Write-File "$d/.git/hooks/pre-push" "#!/bin/sh`ncat > '$d/prepush.marker'`n"
& chmod +x "$d/.git/hooks/pre-push"
$r = Invoke-Git $d @('push', 'origin', 'feat:ok-prepush')
$fwd = if (Test-Path "$d/prepush.marker") { [System.IO.File]::ReadAllText("$d/prepush.marker") } else { '<none>' }
Check 'repo_prepush_runs' ($r.rc -eq 0 -and $fwd -cmatch '^refs/heads/feat [0-9a-f]{40} refs/heads/ok-prepush 0{40}\n$') "rc=$($r.rc) forwarded=[$fwd] stderr=[$($r.err.Trim())]"

$d = New-Work 'repo_prepush_fail'
Write-File "$d/.git/hooks/pre-push" "#!/bin/sh`ncat > /dev/null`necho ran > '$d/prepush.marker'`nexit 1`n"
& chmod +x "$d/.git/hooks/pre-push"
$r = Invoke-Git $d @('push', 'origin', 'feat:no-prepush')
Check 'repo_prepush_exit1_fails' ($r.rc -ne 0 -and (Test-Path "$d/prepush.marker") -and -not (Remote-Has 'no-prepush')) "rc=$($r.rc) marker=$(Test-Path "$d/prepush.marker")"

$d = New-Work 'husky'
Write-File "$d/.husky/pre-push" "#!/bin/sh`ncat > /dev/null`necho ran > '$d/husky.marker'`n"
& chmod +x "$d/.husky/pre-push"
git -C $d config core.hooksPath .husky
$r = Invoke-Git $d @('push', 'origin', 'feat:ok-husky')
Check 'husky_hookspath_runs' ($r.rc -eq 0 -and (Test-Path "$d/husky.marker")) "rc=$($r.rc) marker=$(Test-Path "$d/husky.marker") stderr=[$($r.err.Trim())]"

$d = New-Work 'precommit'
Write-File "$d/.git/hooks/pre-commit" "#!/bin/sh`necho ran > '$d/precommit.marker'`n"
& chmod +x "$d/.git/hooks/pre-commit"
$r = Invoke-Git $d @('commit', '--allow-empty', '-q', '-m', 'x')
Check 'precommit_passthrough_runs' ($r.rc -eq 0 -and (Test-Path "$d/precommit.marker")) "rc=$($r.rc) marker=$(Test-Path "$d/precommit.marker") stderr=[$($r.err.Trim())]"

$d = New-Work 'global_hookspath'
Write-File "$Tmp/global-hooks/pre-commit" "#!/bin/sh`necho ran > '$d/global.marker'`n"
& chmod +x "$Tmp/global-hooks/pre-commit"
Write-File "$Tmp/global.gitconfig" "[core]`n`thooksPath = $Tmp/global-hooks`n"
$r = Invoke-Git $d @('commit', '--allow-empty', '-q', '-m', 'x') @{ GIT_CONFIG_GLOBAL = "$Tmp/global.gitconfig" }
Check 'global_hookspath_runs' ($r.rc -eq 0 -and (Test-Path "$d/global.marker")) "rc=$($r.rc) marker=$(Test-Path "$d/global.marker") stderr=[$($r.err.Trim())]"

# md_chain's git cost: a counting `git` function stands in for the real one.
$CountSh = @'
. "$ROOT/git-hooks/_chain.sh"
git() { echo x >> "$COUNT"; command git "$@"; }
md_chain pre-commit
'@
function Get-ChainCalls([string]$dir, [string]$tag) {
  $c = "$Tmp/count-$tag"
  $null = Invoke-Child -Exe $Bash -Argv @('-c', $CountSh) -Stdin '' -Cwd $dir -Env (Get-GitEnv @{ ROOT = $Root; COUNT = $c })
  if (-not (Test-Path $c)) { return 0 }
  return @(Get-Content $c).Count
}
$d = New-Work 'chain_cost_default'
$n1 = Get-ChainCalls $d 'default'
$d = New-Work 'chain_cost_local'
git -C $d config core.hooksPath .husky
$n2 = Get-ChainCalls $d 'local'
Check 'chain_git_calls' ($n1 -le 2 -and $n2 -eq 1) "default=$n1 (want <= 2) local-hooksPath=$n2 (want 1)"
$hot = @('reference-transaction', 'post-index-change', 'push-to-checkout') | Where-Object { Test-Path -LiteralPath "$Root/git-hooks/$_" }
Check 'chain_hot_hooks_absent' (@($hot).Count -eq 0) "present: $($hot -join ', ')"

# ---- git shim ---------------------------------------------------------------
function Invoke-GitShim([string]$dir, [string[]]$a) {
  return Invoke-Child -Exe $Bash -Argv (@("$Root/shims/git") + $a) -Stdin '' -Cwd $dir -Env (Get-GitEnv @{ PATH = "$Root/shims$Sep$CleanPath" })
}
$GitDeny = Deny 'pushing' 'unknown target'
$Gs = New-Work 'git-shim'
git -C $Gs config alias.p 'push --no-verify'
git -C $Gs config alias.pp '-c core.hooksPath=/x push'
git -C $Gs config alias.st '!git status --short'
function Test-GitShimDeny([string]$name, [string[]]$a, [string]$gone = '') {
  $r = Invoke-GitShim $Gs $a
  $absent = (-not $gone) -or -not (Remote-Has $gone)
  Check $name ($r.rc -eq 1 -and $r.err.TrimEnd() -ceq $GitDeny -and $absent) "rc=$($r.rc) stderr=[$($r.err.Trim())] remote-has=$(-not $absent)"
}
Test-GitShimDeny 'git_no_verify_push_denies' @('push', '--no-verify', 'origin', 'feat:issue/9-nv') 'issue/9-nv'
Test-GitShimDeny 'git_no_verify_abbrev_denies' @('push', '--no-veri', 'origin', 'feat:issue/9-nv') 'issue/9-nv'
Test-GitShimDeny 'git_c_hookspath_push_denies' @('-c', 'core.hooksPath=/x', 'push', 'origin', 'feat:issue/9-hp') 'issue/9-hp'
Test-GitShimDeny 'git_c_hookspath_case_denies' @('-c', 'CORE.HOOKSPATH=/x', 'status')
Test-GitShimDeny 'git_c_attached_hookspath_denies' @('-ccore.hooksPath=/x', 'status')
Test-GitShimDeny 'git_config_env_hookspath_denies' @('--config-env=core.hooksPath=HOME', 'status')
Test-GitShimDeny 'git_config_env_sep_hookspath_denies' @('--config-env', 'core.hookspath=HOME', 'status')
Test-GitShimDeny 'git_alias_no_verify_denies' @('p', 'origin', 'feat:issue/9-al') 'issue/9-al'
Test-GitShimDeny 'git_alias_hookspath_denies' @('pp', 'origin', 'feat:issue/9-ah') 'issue/9-ah'
Test-GitShimDeny 'git_c_alias_no_verify_denies' @('-c', 'alias.q=push --no-verify', 'q', 'origin', 'feat:issue/9-ca') 'issue/9-ca'
Test-GitShimDeny 'git_send_pack_denies' @('send-pack', $Remote, 'feat:refs/heads/main') 'main'
$r = Invoke-GitShim $Gs @('push', '-n', 'origin', 'feat:issue/9-x')
Check 'git_push_dry_run_allows' ($r.rc -eq 0 -and -not (Remote-Has 'issue/9-x')) "rc=$($r.rc) stderr=[$($r.err.Trim())]"
$r = Invoke-GitShim $Gs @('status', '--porcelain')
Check 'git_status_allows' ($r.rc -eq 0 -and $r.err -eq '') "rc=$($r.rc) stderr=[$($r.err.Trim())]"
Write-File "$Gs/a.txt" 'a'
git -C $Gs add a.txt
$r = Invoke-GitShim $Gs @('-c', 'user.email=ag@example.invalid', '-c', 'user.name=ag', 'commit', '-q', '-m', 'x')
Check 'git_commit_allows' ($r.rc -eq 0 -and ((git -C $Gs log -1 --format=%s) -ceq 'x')) "rc=$($r.rc) stderr=[$($r.err.Trim())]"
$r = Invoke-GitShim $Tmp @('-C', $Gs, 'log', '--format=%s')
Check 'git_C_log_allows' ($r.rc -eq 0 -and ($r.out -split "`n") -contains 'init') "rc=$($r.rc) out=[$($r.out)] stderr=[$($r.err.Trim())]"
$r = Invoke-GitShim $Gs @('st')
Check 'git_bang_alias_allows' ($r.rc -eq 0) "rc=$($r.rc) stderr=[$($r.err.Trim())]"

# ---- gh shim ----------------------------------------------------------------
# The stub answers `gh pr view [<pr>] [-R o/r] --json baseRefName --jq .baseRefName`
# from map.txt (`<pr> <base>` per line, `*` for any PR), `gh repo view [o/r] --json
# defaultBranchRef` and `gh api repos/o/r --jq .default_branch` from its
# `DEFAULT <branch>` line, and `gh alias list` from aliases.txt; needrepo makes it
# refuse a pr view without `-R o/r`. Any other call is logged, one argument per
# line, to seen.log: the call the shim let through.
$StubSh = @'
#!/usr/bin/env bash
d="${BASH_SOURCE[0]%/*}"
default() { while read -r n b; do [ "$n" = DEFAULT ] && { echo "$b"; exit 0; }; done < "$d/map.txt"; exit 1; }
if [ "$1" = alias ] && [ "$2" = list ]; then
  [ -f "$d/aliases.txt" ] && cat "$d/aliases.txt"; exit 0
fi
if [ "$1" = repo ] && [ "$2" = view ]; then
  case " $* " in *defaultBranchRef*) [ "$3" = o/r ] && default ;; esac; exit 1
fi
if [ "$1" = api ] && [ "$2" = repos/o/r ]; then
  case " $* " in *.default_branch*) default ;; esac; exit 1
fi
if [ "$1" = pr ] && [ "$2" = view ]; then
  num="$3"; case "$num" in -*) num='*' ;; esac
  if [ -f "$d/needrepo" ]; then case " $* " in *" -R o/r "*) ;; *) exit 1 ;; esac; fi
  while read -r n b; do
    if [ "$n" = "$num" ] || [ "$n" = '*' ]; then
      case " $* " in *" --jq "*) echo "$b" ;; *) echo "{\"baseRefName\":\"$b\"}" ;; esac
      exit 0
    fi
  done < "$d/map.txt"
  exit 1
fi
printf '%s\n' "$@" > "$d/seen.log"
exit 0
'@
function New-Stub([string]$spec, [string]$aliases) {
  $dir = "$Tmp/stub-$([System.Guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $dir | Out-Null
  Write-File "$dir/gh" ($StubSh + "`n")
  & chmod +x "$dir/gh"
  if ($spec.StartsWith('R!')) { $spec = $spec.Substring(2); Write-File "$dir/needrepo" 'o/r' }
  $lines = @()
  if ($spec -ne 'FAIL') { foreach ($e in ($spec -split ',')) { $k, $v = $e -split '=', 2; $lines += "$k $v" } }
  Write-File "$dir/map.txt" (($lines -join "`n") + "`n")
  if ($aliases) { Write-File "$dir/aliases.txt" ($aliases + "`n") }
  return $dir
}
$ShimRepo = New-Work 'shim-repo'
$MainCo = New-Work 'shim-main'; git -C $MainCo checkout -q main
$FeatCo = New-Work 'shim-feat'; git -C $FeatCo checkout -q -b issue/9-x
$DetCo = New-Work 'shim-detached'; git -C $DetCo checkout -q --detach

# A PATH with the shell tools the shims use and no jq.
$NoJq = "$Tmp/nojq-bin"
New-Item -ItemType Directory -Path $NoJq | Out-Null
foreach ($t in 'bash', 'env', 'sed', 'head', 'tr', 'cat', 'grep', 'awk', 'xargs', 'printf') { Add-ToolStub $t $NoJq }
if ($IsWindows) { Copy-Item -LiteralPath $GitBin -Destination "$NoJq/$(Split-Path -Leaf $GitBin)" }
else { New-Item -ItemType SymbolicLink -Path "$NoJq/git" -Target $GitBin | Out-Null }

function Invoke-Shim([string]$spec, [string[]]$a, [string]$cwd = $ShimRepo, [string]$aliases = '', [string]$base = $env:PATH) {
  $stub = New-Stub $spec $aliases
  $path = "$Root/shims$Sep$stub$Sep$base"
  $r = Invoke-Child -Exe $Bash -Argv (@("$Root/shims/gh") + $a) -Stdin '' -Cwd $cwd -Env @{ PATH = $path; GH_REPO = '' }
  $r.stub = $stub
  return $r
}
function Test-ShimDeny([string]$name, [string]$spec, [string[]]$a, [string]$action, [string]$branch, [string]$cwd = $ShimRepo, [string]$aliases = '') {
  $r = Invoke-Shim $spec $a $cwd $aliases
  Check $name ($r.rc -eq 1 -and $r.err.TrimEnd() -eq (Deny $action $branch) -and -not (Test-Path "$($r.stub)/seen.log")) "rc=$($r.rc) stderr=[$($r.err.Trim())] reached=$(Test-Path "$($r.stub)/seen.log")"
}
function Test-ShimAllow([string]$name, [string]$spec, [string[]]$a, [string]$cwd = $ShimRepo, [string]$aliases = '') {
  $r = Invoke-Shim $spec $a $cwd $aliases
  $seen = if (Test-Path "$($r.stub)/seen.log") { [System.IO.File]::ReadAllText("$($r.stub)/seen.log") } else { '<none>' }
  Check $name ($r.rc -eq 0 -and $seen -ceq ((($a -join "`n")) + "`n")) "rc=$($r.rc) stderr=[$($r.err.Trim())] seen=[$seen]"
}

# pr create
Test-ShimDeny 'create_base_staging' '*=develop' @('pr', 'create', '--base', 'staging', '--title', 'x') 'opening a PR' 'staging'
Test-ShimDeny 'create_B_main' '*=develop' @('pr', 'create', '-B', 'main') 'opening a PR' 'main'
Test-ShimDeny 'create_base_eq_main' '*=develop' @('pr', 'create', '--base=main') 'opening a PR' 'main'
Test-ShimDeny 'create_no_base_default_main' 'R!DEFAULT=main' @('-R', 'o/r', 'pr', 'create', '--title', 'x') 'opening a PR' 'main'
Test-ShimDeny 'create_no_base_unresolved' 'FAIL' @('pr', 'create', '--title', 'x') 'opening a PR' 'unknown base'
# pr merge
Test-ShimDeny 'merge_base_production' '5=production' @('pr', 'merge', '5') 'merging a PR' 'production'
Test-ShimDeny 'merge_unresolved' 'FAIL' @('pr', 'merge', '5') 'merging a PR' 'unknown base'
Test-ShimDeny 'merge_no_arg_main_pr' '*=main' @('pr', 'merge', '--squash') 'merging a PR' 'main'
Test-ShimDeny 'merge_R_5' 'R!5=main' @('-R', 'o/r', 'pr', 'merge', '5') 'merging a PR' 'main'
Test-ShimDeny 'merge_repo_after_sub' 'R!5=main' @('pr', 'merge', '5', '--repo', 'o/r') 'merging a PR' 'main'
# pr edit
Test-ShimDeny 'edit_base_main' '*=develop' @('pr', 'edit', '5', '--base', 'main') 'retargeting a PR' 'main'
# gh aliases
Test-ShimDeny 'alias_set_pr_merge' '*=develop' @('alias', 'set', 'mrg', 'pr merge') 'setting a gh alias' 'unknown base'
Test-ShimDeny 'alias_set_flagged_api' '*=develop' @('alias', 'set', '--clobber', 'w', '-R o/r api') 'setting a gh alias' 'unknown base'
Test-ShimDeny 'alias_set_stdin' '*=develop' @('alias', 'set', 'mrg', '-') 'setting a gh alias' 'unknown base'
Test-ShimDeny 'alias_import' '*=develop' @('alias', 'import', 'aliases.yml') 'importing gh aliases' 'unknown base'
Test-ShimDeny 'alias_mrg_main' '5=main' @('mrg', '5') 'merging a PR' 'main' $ShimRepo 'mrg: pr merge'
Test-ShimDeny 'alias_placeholder_sync_main' 'R!DEFAULT=main' @('sy', 'o/r') 'pushing' 'main' $ShimRepo "sy: repo sync `$1"
# gh repo sync
Test-ShimDeny 'repo_sync_default_main' 'R!DEFAULT=main' @('repo', 'sync', 'o/r') 'pushing' 'main'
Test-ShimDeny 'repo_sync_branch_main' '*=develop' @('repo', 'sync', 'o/r', '-b', 'main') 'pushing' 'main'
Test-ShimDeny 'repo_sync_unresolved' 'FAIL' @('repo', 'sync', 'o/r') 'pushing' 'unknown branch'
# gh api
Test-ShimDeny 'api_merge_put' '5=main' @('api', '-X', 'PUT', 'repos/o/r/pulls/5/merge') 'merging a PR' 'main'
Test-ShimDeny 'api_pulls_post_base_main' '*=develop' @('api', 'repos/o/r/pulls', '-f', 'base=main', '-f', 'head=x', '-f', 'title=t') 'opening a PR' 'main'
Test-ShimDeny 'api_pulls_post_no_base' '*=develop' @('api', 'repos/o/r/pulls', '-f', 'head=x') 'opening a PR' 'unknown base'
Test-ShimDeny 'api_pulls_patch_base' '5=develop' @('api', '-X', 'PATCH', 'repos/o/r/pulls/5', '-f', 'base=main') 'retargeting a PR' 'main'
Test-ShimDeny 'api_pulls_patch_current_base' '5=main' @('api', '-X', 'PATCH', 'repos/o/r/pulls/5', '-f', 'title=t') 'retargeting a PR' 'main'
Test-ShimDeny 'api_merges_base_main' '*=develop' @('api', 'repos/o/r/merges', '-f', 'base=main', '-f', 'head=x') 'merging a branch' 'main'
Test-ShimDeny 'api_merges_no_base_default_main' 'DEFAULT=main' @('api', 'repos/o/r/merges', '-f', 'head=x') 'merging a branch' 'main'
Test-ShimDeny 'api_merge_upstream' '*=develop' @('api', 'repos/o/r/merge-upstream', '-f', 'branch=main') 'pushing' 'main'
Test-ShimDeny 'api_rename_path_branch' '*=develop' @('api', 'repos/o/r/branches/main/rename', '-f', 'new_name=x') 'pushing' 'main'
Test-ShimDeny 'api_rename_new_name' '*=develop' @('api', 'repos/o/r/branches/x/rename', '-f', 'new_name=release/2') 'pushing' 'release/2'
Test-ShimDeny 'api_git_refs_post' '*=develop' @('api', 'repos/o/r/git/refs', '-f', 'ref=refs/heads/release/1.2', '-f', 'sha=abc') 'pushing' 'release/1.2'
Test-ShimDeny 'api_git_refs_heads_patch' '*=develop' @('api', '-X', 'PATCH', 'repos/o/r/git/refs/heads/main', '-f', 'sha=abc') 'pushing' 'main'
Test-ShimDeny 'api_contents_put_main' '*=develop' @('api', '-X', 'PUT', 'repos/o/r/contents/f.txt', '-f', 'branch=main', '-f', 'message=m', '-f', 'content=Zg==') 'pushing' 'main'
Test-ShimDeny 'api_contents_no_branch_default_main' 'DEFAULT=main' @('api', '-X', 'PUT', 'repos/o/r/contents/f.txt', '-f', 'message=m') 'pushing' 'main'
Test-ShimDeny 'api_contents_no_branch_unresolved' 'FAIL' @('api', '-X', 'PUT', 'repos/o/r/contents/f.txt', '-f', 'message=m') 'pushing' 'unknown branch'
Test-ShimDeny 'api_pulls_input' '*=develop' @('api', 'repos/o/r/pulls', '--input', 'body.json') 'opening a PR' 'unknown base'
Test-ShimDeny 'api_contents_input' '*=develop' @('api', '-X', 'PUT', 'repos/o/r/contents/f.txt', '--input', 'body.json') 'pushing' 'unknown branch'
Test-ShimDeny 'api_field_at_file' '*=develop' @('api', 'repos/o/r/pulls', '-F', 'base=@base.txt') 'opening a PR' 'unknown base'
Test-ShimDeny 'api_branch_placeholder_main' '*=develop' @('api', '-X', 'PATCH', 'repos/{owner}/{repo}/git/refs/heads/{branch}', '-f', 'sha=x') 'pushing' 'main' $MainCo
Test-ShimDeny 'api_rename_placeholder_main' '*=develop' @('api', '-X', 'POST', 'repos/{owner}/{repo}/branches/{branch}/rename', '-f', 'new_name=issue/10-y') 'pushing' 'main' $MainCo
Test-ShimDeny 'api_branch_placeholder_unresolved' '*=develop' @('api', '-X', 'PATCH', 'repos/{owner}/{repo}/git/refs/heads/{branch}', '-f', 'sha=x') 'pushing' 'unknown branch' $DetCo
Test-ShimDeny 'api_ghes_merge_put' '5=main' @('api', '-X', 'PUT', 'https://ghe.example.com/api/v3/repos/o/r/pulls/5/merge') 'merging a PR' 'main'
Test-ShimDeny 'api_ghes_graphql_merge' '*=develop' @('api', 'https://ghe.example.com/api/graphql', '-f', 'query=mutation { mergePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }') 'merging a PR' 'unknown base'
Test-ShimDeny 'api_graphql_merge_mutation' '*=develop' @('api', 'graphql', '-f', 'query=mutation { mergePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }') 'merging a PR' 'unknown base'
Test-ShimDeny 'api_graphql_enqueue' '*=develop' @('api', 'graphql', '-f', 'query=mutation { enqueuePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }') 'merging a PR' 'unknown base'
Test-ShimDeny 'api_graphql_delete_ref' '*=develop' @('api', 'graphql', '-f', 'query=mutation { deleteRef(input: {refId: "x"}) { clientMutationId } }') 'pushing' 'unknown branch'
Test-ShimDeny 'api_graphql_create_pr_base' '*=develop' @('api', 'graphql', '-f', 'query=mutation($b: String!) { createPullRequest(input: {repositoryId: "r", baseRefName: $b, headRefName: "x", title: "t"}) { clientMutationId } }', '-f', 'b=develop') 'opening a PR' 'unknown base'
Test-ShimDeny 'api_graphql_update_pr_base_field' '*=develop' @('api', 'graphql', '-f', 'query=mutation($i: UpdatePullRequestInput!) { updatePullRequest(input: $i) { clientMutationId } }', '-F', 'i[baseRefName]=main') 'retargeting a PR' 'unknown base'
Test-ShimDeny 'api_graphql_query_file' '*=develop' @('api', 'graphql', '-F', 'query=@q.graphql') 'running a GraphQL query from a file' 'unknown branch'
Test-ShimDeny 'api_graphql_input' '*=develop' @('api', 'graphql', '--input', 'q.json') 'running a GraphQL query from a file' 'unknown branch'

# allows: the stub sees the argv unchanged
Test-ShimAllow 'create_base_develop' '*=develop' @('pr', 'create', '--base', 'develop', '--title', 'x')
Test-ShimAllow 'create_title_subst_base_develop' '*=develop' @('pr', 'create', '--title', 'x --base main', '--body', 'merge 5 -B main', '--base', 'develop')
Test-ShimAllow 'merge_develop' '5=develop' @('pr', 'merge', '5', '--merge')
Test-ShimAllow 'merge_driver_shape' 'R!12=develop' @('-R', 'o/r', 'pr', 'merge', '12', '--squash', '--subject', 'feat: x (#12)', '--body', "Closes #12.`nSecond line.", '--delete-branch')
Test-ShimAllow 'api_pulls_get' '*=develop' @('api', 'repos/o/r/pulls/5')
Test-ShimAllow 'api_get_pulls_fields' 'FAIL' @('api', '-X', 'GET', 'repos/o/r/pulls', '-f', 'state=closed', '-f', 'head=o:issue/9-x')
Test-ShimAllow 'api_get_contents_ref' 'FAIL' @('api', '-X', 'GET', 'repos/o/r/contents/README.md', '-f', 'ref=develop')
Test-ShimAllow 'api_paginate_get_fields' 'FAIL' @('api', '--paginate', '-X', 'GET', 'repos/o/r/pulls', '-F', 'per_page=100')
Test-ShimAllow 'api_graphql_read_base_ref' 'FAIL' @('api', 'graphql', '-f', 'query={ repository(owner: "o", name: "r") { pullRequest(number: 5) { baseRefName } } }')
Test-ShimAllow 'api_branch_placeholder_feature' '*=develop' @('api', '-X', 'PATCH', 'repos/{owner}/{repo}/git/refs/heads/{branch}', '-f', 'sha=x') $FeatCo
Test-ShimAllow 'api_rename_placeholder_feature' '*=develop' @('api', '-X', 'POST', 'repos/{owner}/{repo}/branches/{branch}/rename', '-f', 'new_name=issue/10-y') $FeatCo
Test-ShimAllow 'alias_mrg_develop' '5=develop' @('mrg', '5') $ShimRepo 'mrg: pr merge'
Test-ShimAllow 'alias_bang_passthrough' 'FAIL' @('ig', 'bug') $ShimRepo "ig: '!gh pr merge `"`$1`"'"
Test-ShimAllow 'alias_set_view' 'FAIL' @('alias', 'set', 'pv', 'pr view')
Test-ShimAllow 'alias_set_shell' 'FAIL' @('alias', 'set', '--shell', 'm', 'gh pr merge "$1"')
Test-ShimAllow 'repo_sync_branch_feature' 'FAIL' @('repo', 'sync', 'o/r', '--branch', 'issue/9-x')
Test-ShimAllow 'repo_sync_local' 'FAIL' @('repo', 'sync')

# protectedBranches needs jq: without it the sed fallback names the dropped key once.
$Pb = New-Work 'shim-pb-nojq'
Write-File "$Pb/.milestone-config/driver.json" "{`n  `"protectedBranch`": `"main`",`n  `"integrationBranch`": `"develop`",`n  `"protectedBranches`": [`"live`"]`n}`n"
$r = Invoke-Shim '*=develop' @('pr', 'create', '--base', 'main') $Pb '' $NoJq
$el = @($r.err.TrimEnd() -split "`n")
Check 'protected_branches_no_jq_warns' ($r.rc -eq 1 -and $el.Count -eq 2 -and $el[0] -clike '*protectedBranches*' -and $el[1] -ceq (Deny 'opening a PR' 'main')) "rc=$($r.rc) stderr=[$($r.err.Trim())]"

# ---- hooks/agent-env --------------------------------------------------------
$Check = @'
unset GIT_CONFIG_COUNT
[ -n "$PRESET" ] && { export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=x.y GIT_CONFIG_VALUE_0=z; }
. "$ENVFILE"
echo "count=$GIT_CONFIG_COUNT"
echo "key0=$GIT_CONFIG_KEY_0"
echo "xy=$(git config --get x.y)"
echo "hooks=$(git config --get core.hooksPath)"
[ "$(cd "${PATH%%:*}" && pwd -P)" = "$(cd "$ROOT/shims" && pwd -P)" ] && echo shimfirst=yes
'@
function Invoke-EnvFile([string]$envFile, [bool]$preset, [string]$root = $Root) {
  return Invoke-Child -Exe $Bash -Argv @('-c', $Check) -Stdin '' -Cwd $ShimRepo -Env @{ ENVFILE = $envFile; ROOT = $root; PRESET = $(if ($preset) { '1' } else { '' }) }
}
function Get-Line([string]$out, [string]$key) {
  $l = $out -split "`n" | Where-Object { $_ -like "$key=*" } | Select-Object -First 1
  if (-not $l) { return '' }
  return ([string]$l).Substring($key.Length + 1).Trim() -replace '\\', '/'
}
$AgentEnv = Join-Path $Root 'hooks/agent-env'

$f = "$Tmp/env-writes"
$r = Invoke-Leg -Script $AgentEnv -Cwd $ShimRepo -Env @{ CLAUDE_ENV_FILE = $f; CLAUDE_PLUGIN_ROOT = $Root }
$s = Invoke-EnvFile $f $false
Check 'agent_env_writes' ($r.rc -eq 0 -and (Get-Line $s.out 'count') -ceq '1' -and (Get-Line $s.out 'key0') -ceq 'core.hooksPath' -and (Get-Line $s.out 'shimfirst') -ceq 'yes' -and (Get-Line $s.out 'hooks') -ceq "$Root/git-hooks") "rc=$($r.rc) out=[$($s.out)] err=[$($s.err)]"

$f = "$Tmp/env-count1"
$r = Invoke-Leg -Script $AgentEnv -Cwd $ShimRepo -Env @{ CLAUDE_ENV_FILE = $f; CLAUDE_PLUGIN_ROOT = $Root }
$s = Invoke-EnvFile $f $true
Check 'agent_env_appends_after_count_1' ($r.rc -eq 0 -and (Get-Line $s.out 'count') -ceq '2' -and (Get-Line $s.out 'key0') -ceq 'x.y' -and (Get-Line $s.out 'xy') -ceq 'z' -and (Get-Line $s.out 'hooks') -ceq "$Root/git-hooks") "rc=$($r.rc) out=[$($s.out)] err=[$($s.err)]"

$f = "$Tmp/env-unset"
$r = Invoke-Leg -Script $AgentEnv -Cwd $ShimRepo -Env @{ CLAUDE_ENV_FILE = ''; CLAUDE_PLUGIN_ROOT = $Root }
Check 'agent_env_unset_file' ($r.rc -eq 0 -and $r.out -eq '' -and @($r.err.Trim() -split "`n").Count -eq 1 -and $r.err.Trim() -ne '' -and -not (Test-Path $f)) "rc=$($r.rc) out=[$($r.out)] err=[$($r.err)]"

$f = "$Tmp/env-idem"
$envArg = @{ CLAUDE_ENV_FILE = $f; CLAUDE_PLUGIN_ROOT = $Root }
$null = Invoke-Leg -Script $AgentEnv -Cwd $ShimRepo -Env $envArg
$first = Get-Content $f -Raw
$r = Invoke-Leg -Script $AgentEnv -Cwd $ShimRepo -Env $envArg
$s = Invoke-EnvFile $f $false
Check 'agent_env_idempotent' ($r.rc -eq 0 -and (Get-Content $f -Raw) -ceq $first -and (Get-Line $s.out 'count') -ceq '1') "rc=$($r.rc) file=[$(Get-Content $f -Raw)] out=[$($s.out)]"

# Both lines take the script's own root, quoted: a space and a single quote round-trip.
$Weird = "$Tmp/it's a root"
New-Item -ItemType Directory -Path "$Weird/hooks", "$Weird/shims" | Out-Null
foreach ($x in 'sh', 'ps1') { Copy-Item -LiteralPath "$Root/hooks/agent-env.$x" -Destination "$Weird/hooks/agent-env.$x" }
$f = "$Tmp/env-weird"
$r = Invoke-Leg -Script "$Weird/hooks/agent-env" -Cwd $ShimRepo -Env @{ CLAUDE_ENV_FILE = $f; CLAUDE_PLUGIN_ROOT = $Root }
$s = Invoke-EnvFile $f $false $Weird
Check 'agent_env_quoted_root' ($r.rc -eq 0 -and (Get-Line $s.out 'shimfirst') -ceq 'yes' -and (Get-Line $s.out 'hooks') -ceq "$Weird/git-hooks") "rc=$($r.rc) out=[$($s.out)] err=[$($s.err)] file=[$(if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -Raw })]"

Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "agent-gate ($Leg): $pass passed, $fail failed"
if ($fail -eq 0) { exit 0 } else { exit 1 }
