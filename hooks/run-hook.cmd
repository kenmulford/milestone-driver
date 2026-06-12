: << 'CMDBLOCK'
@echo off
REM milestone-driver cross-platform polyglot launcher.
REM Windows: cmd runs this batch half (bash first, then pwsh, else exit 0).
REM Unix: bash runs the sh half below ( : is a no-op; heredoc swallows the batch ).
REM Usage: run-hook.cmd <gate>   (gate = base name, e.g. force-subagent)
if "%~1"=="" (echo run-hook.cmd: missing gate name>&2& exit /b 1)
set "HOOK_DIR=%~dp0"
set "GATE=%~1"
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%GATE%.sh"
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%GATE%.sh"
    exit /b %ERRORLEVEL%
)
where bash >nul 2>nul && (
    bash "%HOOK_DIR%%GATE%.sh"
    exit /b %ERRORLEVEL%
)
where pwsh >nul 2>nul && (
    pwsh -NoProfile -File "%HOOK_DIR%%GATE%.ps1"
    exit /b %ERRORLEVEL%
)
exit /b 0
CMDBLOCK

# Unix: bash ran this file, so bash exists -> run the gate's .sh.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "${HOOK_DIR}/$1.sh"
