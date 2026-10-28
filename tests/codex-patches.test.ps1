param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1'); Set-Leg $Leg
$root = Split-Path $PSScriptRoot -Parent
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureName = 'milestone-driver-patches-' + [guid]::NewGuid().ToString()
$tmp = Join-Path $tempRoot $fixtureName
$utf8 = [Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
New-Item -ItemType Directory -Path "$tmp/.milestone-config" -Force | Out-Null
[IO.File]::WriteAllText("$tmp/.milestone-config/driver.json", '{"sourceGlobs":["app/**","spec/**","docs/**"]}', $utf8)
$env:CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT = $null
$env:CLAUDE_HOOK_DISABLE_NO_BOM = $null
function Check([string]$name, [string]$gate, [hashtable]$payload, [int]$want, [hashtable]$envVars = @{}) {
    $r = Invoke-Spawn -Script "$root/hooks/$gate" -Stdin ($payload | ConvertTo-Json -Depth 10 -Compress) -Cwd $tmp -Env $envVars
    if ($r.rc -eq $want -and ($want -ne 2 -or $r.err -match 'milestone-driver:') -and $r.out -eq '') { $script:pass++ }
    else { $script:fail++; Write-Host "FAIL $name : rc=$($r.rc) want=$want err=[$($r.err)] out=[$($r.out)]" }
}
function Patch([string]$body) { return @{tool_name='apply_patch'; cwd=$tmp; tool_input=@{command="*** Begin Patch`n$body`n*** End Patch"}} }
try {
    Check 'add source' force-subagent (Patch "*** Add File: app/a.rb`n+puts 1") 2
    Check 'update source' force-subagent (Patch "*** Update File: app/a.rb`n@@`n-old`n+new") 2
    Check 'delete source' force-subagent (Patch '*** Delete File: spec/a_spec.rb') 2
    Check 'allowed first does not mask later source' force-subagent (Patch "*** Add File: docs/a.md`n+doc`n*** Update File: app/a.rb`n@@`n-a`n+b") 2
    Check 'move into source' force-subagent (Patch "*** Update File: notes/a.md`n*** Move to: app/a.rb`n@@`n-a`n+b") 2
    Check 'move out of source' force-subagent (Patch "*** Update File: app/a.rb`n*** Move to: docs/a.md`n@@`n-a`n+b") 2
    Check 'normalized relative escape from docs' force-subagent (Patch "*** Add File: ./docs/../app/a.rb`n+a") 2
    Check 'normalized backslashes' force-subagent (Patch "*** Add File: .\docs\..\app\a.rb`n+a") 2
    Check 'normalized absolute path' force-subagent (Patch "*** Add File: $tmp/docs/../app/a.rb`n+a") 2
    Check 'normalized docs exemption' force-subagent (Patch "*** Add File: app/../docs/a.md`n+a") 0
    Check 'docs .claude and Obsidian exemptions' force-subagent (Patch "*** Add File: docs/a.md`n+a`n*** Add File: .claude/a.md`n+a`n*** Add File: Obsidian/a.md`n+a") 0
    Check 'content is not a header' force-subagent (Patch "*** Add File: notes/a.md`n+*** Delete File: app/a.rb`n+*** Move to: app/b.rb") 0
    foreach ($field in @('agent_id','agent_type','parent_session_id')) {
        $p = Patch '*** Delete File: app/a.rb'; $p[$field] = 'child'
        Check "legacy child $field" force-subagent $p 0
    }
    Check 'override' force-subagent (Patch '*** Delete File: app/a.rb') 0 @{CLAUDE_HOOK_DISABLE_FORCE_SUBAGENT='1'}
    $p = Patch '*** Delete File: app/a.rb'; $p.cwd = "$tmp/missing"
    Check 'missing profile' force-subagent $p 0
    Check 'legacy normalized source' force-subagent @{cwd=$tmp; tool_input=@{file_path='docs/../app/a.rb'}} 2
    Check 'legacy normalized docs' force-subagent @{cwd=$tmp; tool_input=@{file_path='app/../docs/a.md'}} 0
    $bom = [char]0xfeff
    Check 'add leading BOM' no-bom (Patch "*** Add File: notes/a.md`n+$($bom)bad") 2
    Check 'later file leading BOM' no-bom (Patch "*** Add File: notes/a.md`n+clean`n*** Add File: notes/b.md`n+$($bom)bad") 2
    Check 'update leading replacement BOM' no-bom (Patch "*** Update File: notes/a.md`n@@`n-old`n+$($bom)bad") 2
    Check 'second replacement block BOM' no-bom (Patch "*** Update File: notes/a.md`n@@`n-old`n+clean`n context`n-old2`n+$($bom)bad") 2
    Check 'replacement after deletion starts new block' no-bom (Patch "*** Update File: notes/a.md`n@@`n+clean`n-old`n+$($bom)bad") 2
    Check 'add embedded BOM' no-bom (Patch "*** Add File: notes/a.md`n+clean$($bom)ok") 0
    Check 'add later line BOM' no-bom (Patch "*** Add File: notes/a.md`n+clean`n+$($bom)ok") 0
    Check 'add blank first line before BOM' no-bom (Patch "*** Add File: notes/a.md`n+`n+$($bom)ok") 0
    Check 'update later line in same block BOM' no-bom (Patch "*** Update File: notes/a.md`n@@`n-old`n+clean`n+$($bom)ok") 0
    Check 'update embedded BOM' no-bom (Patch "*** Update File: notes/a.md`n@@`n-old`n+clean$($bom)ok") 0
    Check 'context and deleted BOM are allowed' no-bom (Patch "*** Update File: notes/a.md`n@@`n $($bom)context`n-$($bom)old`n+clean") 0
    Check 'delete and move without additions' no-bom (Patch "*** Delete File: notes/a.md`n*** Update File: notes/b.md`n*** Move to: notes/c.md") 0
    Check 'BOM override' no-bom (Patch "*** Add File: notes/a.md`n+$($bom)bad") 0 @{CLAUDE_HOOK_DISABLE_NO_BOM='1'}
    Check 'legacy Write BOM' no-bom @{tool_name='Write'; tool_input=@{content="$($bom)bad"}} 2
    Check 'legacy Edit BOM' no-bom @{tool_name='Edit'; tool_input=@{new_string="$($bom)bad"}} 2
    Check 'legacy MultiEdit later BOM' no-bom @{tool_name='MultiEdit'; tool_input=@{edits=@(@{new_string='clean'},@{new_string="$($bom)bad"})}} 2
    Check 'legacy clean Write' no-bom @{tool_name='Write'; tool_input=@{content='clean'}} 0
    Check 'legacy embedded Edit BOM' no-bom @{tool_name='Edit'; tool_input=@{new_string="clean$($bom)ok"}} 0
    $crlf = @{tool_name='apply_patch'; cwd=$tmp; tool_input=@{command="*** Begin Patch`r`n*** Add File: app/a.rb`r`n+$($bom)bad`r`n*** End Patch`r`n"}}
    Check 'CRLF patch source blocked' force-subagent $crlf 2
    Check 'trailing space after path' force-subagent (Patch "*** Add File: app/a.rb `n+a") 2
    [IO.File]::WriteAllText("$tmp/.milestone-config/driver.json", '{"sourceGlobs":["*.rb","docs/**"]}', $utf8)
    Check 'trailing space vs suffix glob' force-subagent (Patch "*** Add File: lib/a.rb `n+a") 2
    [IO.File]::WriteAllText("$tmp/.milestone-config/driver.json", '{"sourceGlobs":["app/**","spec/**","docs/**"]}', $utf8)
    Check 'indented header' force-subagent (Patch "  *** Update File: app/a.rb`n@@`n-a`n+b") 2
    Check 'indented move header' force-subagent (Patch "*** Update File: notes/a.md`n  *** Move to: app/a.rb`n@@`n-a`n+b") 2
    Check 'CRLF patch BOM blocked' no-bom $crlf 2
    Check 'unknown tool ignores patch-like command' no-bom @{tool_name='Bash';tool_input=@{command="*** Begin Patch`n*** Add File: a`n+$($bom)bad`n*** End Patch"}} 0
} finally {
    $resolved = [IO.Path]::GetFullPath($tmp)
    $parent = [IO.Path]::GetDirectoryName($resolved)
    if ($parent -ne $tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) -or [IO.Path]::GetFileName($resolved) -notmatch '^milestone-driver-patches-[0-9a-f-]{36}$') { throw "Unsafe fixture cleanup path: $resolved" }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "codex-patches ($Leg): $pass passed, $fail failed"
if ($fail) { exit 1 }
