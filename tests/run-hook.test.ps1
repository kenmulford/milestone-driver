param([ValidateSet('ps1', 'sh')][string]$Leg = 'ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1'); Set-Leg $Leg
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../hooks/run-hook.cmd'))
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureName = 'milestone-driver-launcher-' + [guid]::NewGuid().ToString()
$tmp = Join-Path $tempRoot $fixtureName
$utf8 = [Text.UTF8Encoding]::new($false)
$pass = 0; $fail = 0
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    if ($IsWindows) {
        $bash = (Get-BashBin).Replace('/', '\')
        $pwshDir = Split-Path (Get-Command pwsh).Source -Parent
        Copy-Item -LiteralPath "$env:SystemRoot/System32/where.exe" -Destination $tmp
        foreach ($branch in @('git64','git32','path-bash','path-pwsh','none')) {
            # Relocate fixed interpreter dependencies in an isolated copy; run real interpreters.
            $first = if ($branch -eq 'git64') { $bash } else { Join-Path $tmp 'missing64.exe' }
            $second = if ($branch -eq 'git32') { $bash } else { Join-Path $tmp 'missing32.exe' }
            $launcher = $source.Replace('C:\Program Files\Git\bin\bash.exe',$first).Replace('C:\Program Files (x86)\Git\bin\bash.exe',$second)
            [IO.File]::WriteAllText("$tmp/run-hook.cmd", $launcher, $utf8)
            $pathValue = switch ($branch) { 'path-bash' { "$(Split-Path $bash -Parent);$tmp" } 'path-pwsh' { "$pwshDir;$tmp" } default { $tmp } }
            foreach ($code in @(0,2,7)) {
                [IO.File]::WriteAllText("$tmp/fixture.sh", "printf bash`nexit $code`n", $utf8)
                [IO.File]::WriteAllText("$tmp/fixture.ps1", "[Console]::Write('pwsh'); exit $code`n", $utf8)
                $r = Invoke-Child -Exe $env:ComSpec -Argv @('/d','/c',(Join-Path $tmp 'run-hook.cmd'),'fixture') -Stdin '' -Cwd $tmp -Env @{PATH=$pathValue}
                $want = if ($branch -eq 'none') { 0 } else { $code }
                $wantOut = switch ($branch) { 'none' { '' } 'path-pwsh' { 'pwsh' } default { 'bash' } }
                if ($r.rc -eq $want -and $r.out -eq $wantOut) { $pass++ }
                else { $fail++; Write-Host "FAIL $branch exit $code : rc=$($r.rc) want=$want out=[$($r.out)] err=[$($r.err)]" }
            }
        }
    }
    foreach ($code in @(0,2,7)) {
        [IO.File]::WriteAllText("$tmp/run-hook.cmd", $source, $utf8)
        [IO.File]::WriteAllText("$tmp/fixture.sh", "exit $code`n", $utf8)
        $r = Invoke-Child -Exe (Get-BashBin) -Argv @("$tmp/run-hook.cmd",'fixture') -Stdin '' -Cwd $tmp -Env @{}
        if ($r.rc -eq $code) { $pass++ } else { $fail++; Write-Host "FAIL Unix exit $code : rc=$($r.rc) err=[$($r.err)]" }
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($tmp)
    $parent = [IO.Path]::GetDirectoryName($resolved)
    if ($parent -ne $tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) -or [IO.Path]::GetFileName($resolved) -notmatch '^milestone-driver-launcher-[0-9a-f-]{36}$') { throw "Unsafe fixture cleanup path: $resolved" }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "run-hook ($Leg): $pass passed, $fail failed"
if ($fail) { exit 1 }
