# milestone-driver - shared test-runner helpers. Dot-source, then Set-Leg.
# Invoke-Leg runs the script under test for the runner's leg and returns
# @{ out; err; rc }: `ps1` in-process (Console streams redirected, cwd and env
# restored after), `sh` as a bash child (MD_BASH_BIN overrides the interpreter,
# the macOS /bin/bash 3.2 venue). Invoke-Spawn is the out-of-process pwsh path
# for a script that must own its process (render-daemon).
Set-StrictMode -Version Latest
$script:MdLeg = 'ps1'
$script:MdUtf8 = [System.Text.UTF8Encoding]::new($false)

function Set-Leg([string]$leg) {
  if ($leg -notin @('ps1', 'sh')) { throw "unknown leg [$leg]" }
  $script:MdLeg = $leg
}
function Get-Leg { return $script:MdLeg }
function Get-BashBin {
  if ($env:MD_BASH_BIN) { return $env:MD_BASH_BIN }
  if ($IsWindows) {
    # PATH `bash` on Windows is the WSL launcher; the twins ship for Git's bash.
    foreach ($c in @('C:/Program Files/Git/bin/bash.exe', 'C:/Program Files (x86)/Git/bin/bash.exe')) {
      if (Test-Path -LiteralPath $c) { return $c }
    }
  }
  return 'bash'
}

# Invoke-Leg -Script <path without extension> [-Args] [-Stdin] [-Cwd] [-Env]
function Invoke-Leg {
  param(
    [Parameter(Mandatory)][string]$Script,
    [string[]]$Args = @(),
    [string]$Stdin = '',
    [string]$Cwd = '',
    [hashtable]$Env = @{}
  )
  if ($script:MdLeg -eq 'sh') {
    return Invoke-Child -Exe (Get-BashBin) -Argv (@("$Script.sh") + $Args) -Stdin $Stdin -Cwd $Cwd -Env $Env
  }
  return Invoke-InProcess -Path "$Script.ps1" -Args $Args -Stdin $Stdin -Cwd $Cwd -Env $Env
}

function Invoke-Spawn {
  param(
    [Parameter(Mandatory)][string]$Script,
    [string[]]$Args = @(),
    [string]$Stdin = '',
    [string]$Cwd = '',
    [hashtable]$Env = @{}
  )
  if ($script:MdLeg -eq 'sh') {
    return Invoke-Child -Exe (Get-BashBin) -Argv (@("$Script.sh") + $Args) -Stdin $Stdin -Cwd $Cwd -Env $Env
  }
  return Invoke-Child -Exe (Get-Command pwsh).Source -Argv (@('-NoProfile', '-File', "$Script.ps1") + $Args) -Stdin $Stdin -Cwd $Cwd -Env $Env
}

function Invoke-InProcess {
  param([string]$Path, [string[]]$Args, [string]$Stdin, [string]$Cwd, [hashtable]$Env)
  $oldIn = [Console]::In; $oldOut = [Console]::Out; $oldErr = [Console]::Error
  $sw = [System.IO.StringWriter]::new(); $se = [System.IO.StringWriter]::new()
  $oldCwd = (Get-Location).Path
  $saved = @{}
  foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
  $rc = 0
  $pipe = ''
  try {
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    if ($Cwd) { Set-Location -LiteralPath $Cwd }
    [Console]::SetIn([System.IO.StringReader]::new($Stdin))
    [Console]::SetOut($sw); [Console]::SetError($se)
    $global:LASTEXITCODE = 0
    $pipe = (& $Path @Args | Out-String)
    $rc = $global:LASTEXITCODE
  } catch {
    $se.Write($_.Exception.Message)
    $rc = 1
  } finally {
    [Console]::SetIn($oldIn); [Console]::SetOut($oldOut); [Console]::SetError($oldErr)
    Set-Location -LiteralPath $oldCwd
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
  return @{ out = ($sw.ToString() + $pipe); err = $se.ToString(); rc = $rc }
}

function Invoke-Child {
  param([string]$Exe, [string[]]$Argv, [string]$Stdin, [string]$Cwd, [hashtable]$Env)
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $Exe
  foreach ($a in $Argv) { [void]$psi.ArgumentList.Add($a) }
  if ($Cwd) { $psi.WorkingDirectory = $Cwd }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardInputEncoding = $script:MdUtf8
  $psi.StandardOutputEncoding = $script:MdUtf8
  $psi.StandardErrorEncoding = $script:MdUtf8
  foreach ($k in $Env.Keys) { $psi.Environment[$k] = $Env[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($Stdin)
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{ out = $outTask.GetAwaiter().GetResult(); err = $errTask.GetAwaiter().GetResult(); rc = $p.ExitCode }
}
