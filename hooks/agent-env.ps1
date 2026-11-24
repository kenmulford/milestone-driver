#!/usr/bin/env pwsh
# milestone-driver - agent-env (SessionStart, every source), twin of agent-env.sh:
# appends the shim PATH line and the three GIT_CONFIG_* lines to $env:CLAUDE_ENV_FILE,
# which Claude Code sources (in bash) before each Bash command. Never gates.
$envFile = $env:CLAUDE_ENV_FILE
if (-not $envFile) {
    [Console]::Error.WriteLine('milestone-driver agent-env: CLAUDE_ENV_FILE is unset; the gh shim and git hooks are not installed for this session.')
    exit 0
}
$root = ((Resolve-Path (Join-Path $PSScriptRoot '..')).Path) -replace '\\', '/'
# Git Bash splits PATH on `:`, so the shim directory is written as a POSIX path;
# Git for Windows resolves core.hooksPath natively, so it keeps the C:/ form.
$posix = $root
if ($posix -match '^([A-Za-z]):/(.*)$') { $posix = '/' + $matches[1].ToLowerInvariant() + '/' + $matches[2] }
$q = { param($s) $s.Replace("'", "'\''") }
$pathLine = "export PATH='" + (& $q $posix) + "/shims':`"`$PATH`""
if (Test-Path -LiteralPath $envFile) {
    $held = [System.IO.File]::ReadAllLines($envFile)
    if ($held -ccontains $pathLine) { exit 0 }
}
$lines = @(
    $pathLine,
    'export GIT_CONFIG_KEY_${GIT_CONFIG_COUNT:-0}=core.hooksPath',
    ('export GIT_CONFIG_VALUE_${GIT_CONFIG_COUNT:-0}=''' + (& $q $root) + '/git-hooks'''),
    'export GIT_CONFIG_COUNT=$(( ${GIT_CONFIG_COUNT:-0} + 1 ))'
)
try { [System.IO.File]::AppendAllText($envFile, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false)) } catch { }
exit 0
