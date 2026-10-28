param([ValidateSet('ps1','sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1'); Set-Leg $Leg
$root = Split-Path $PSScriptRoot -Parent
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tmp = Join-Path $tempRoot ('milestone-driver-bodyfile-' + [guid]::NewGuid().ToString())
$utf8 = [Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
New-Item -ItemType Directory -Path $tmp | Out-Null
function Check([string]$name,[string]$file,[int]$want,[string]$quote = "'") {
    $payload = @{tool_name='Bash';cwd=$tmp;tool_input=@{command="gh pr create --base develop --body-file $quote$file$quote"}} | ConvertTo-Json -Compress
    $r = Invoke-Leg -Script "$root/hooks/code-review-gate" -Stdin $payload -Cwd $tmp -Env @{CLAUDE_HOOK_DISABLE_CODE_REVIEW_GATE=''}
    if ($r.rc -eq $want -and $r.out -eq '' -and (($want -eq 0 -and $r.err -eq '') -or ($want -eq 2 -and $r.err -match "missing the required '## Code Review' section"))) { $script:pass++ }
    else { $script:fail++; Write-Host "FAIL $name rc=$($r.rc) want=$want out=[$($r.out)] err=[$($r.err)]" }
}
try {
    $bad = Join-Path $tmp 'bad.md'; $good = Join-Path $tmp 'good.md'
    [IO.File]::WriteAllText($bad,'No review section',$utf8)
    [IO.File]::WriteAllText($good,"## Code Review`n/code-review run: yes`n",$utf8)
    Check 'relative unreadable body' 'bad.md' 2
    Check 'native absolute unreadable body' $bad 2
    Check 'slash absolute unreadable body' ($bad.Replace('\','/')) 2
    Check 'native absolute reviewed body' $good 0
    Check 'slash absolute reviewed body' ($good.Replace('\','/')) 0
    Check 'truly missing absolute file' (Join-Path $tmp 'missing.md') 0
    if ($IsWindows) {
        Check 'drive-rooted unreadable body' $bad.Substring(2) 2
        Check 'drive-rooted reviewed body' $good.Substring(2) 0
    }
    $spacedDir = Join-Path $tmp 'body files'
    New-Item -ItemType Directory -Path $spacedDir | Out-Null
    $spacedBad = Join-Path $spacedDir 'bad.md'; $spacedGood = Join-Path $spacedDir 'good.md'
    [IO.File]::WriteAllText($spacedBad,'No review section',$utf8)
    [IO.File]::WriteAllText($spacedGood,"## Code Review`n/code-review run: yes`n",$utf8)
    foreach ($quote in @("'",'"')) {
        Check "absolute spaces $quote missing review" $spacedBad 2 $quote
        Check "absolute spaces $quote reviewed" $spacedGood 0 $quote
        Check "relative spaces $quote missing review" (Join-Path 'body files' 'bad.md') 2 $quote
        Check "relative spaces $quote reviewed" (Join-Path 'body files' 'good.md') 0 $quote
        Check "missing spaced path $quote" (Join-Path $spacedDir 'missing.md') 0 $quote
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($tmp)
    if ([IO.Path]::GetDirectoryName($resolved) -ne $tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) -or [IO.Path]::GetFileName($resolved) -notmatch '^milestone-driver-bodyfile-[0-9a-f-]{36}$') { throw "Unsafe fixture cleanup path: $resolved" }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "body-file-paths ($Leg): $pass passed, $fail failed"
if ($fail) { exit 1 }
