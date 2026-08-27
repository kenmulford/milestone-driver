# milestone-driver - shared test-runner helpers. Dot-source, then Set-Leg.
# Invoke-Leg runs the script under test for the runner's leg and returns
# @{ out; err; rc }: `ps1` in-process (Console streams redirected, cwd and env
# restored after), `sh` as a bash child (MD_BASH_BIN overrides the interpreter,
# the macOS /bin/bash 3.2 venue). Invoke-Spawn is the out-of-process pwsh path
# for a script that must own its process or writes raw bytes through
# [Console]::OpenStandardOutput(), which in-process capture cannot see.
$script:MdLeg = 'ps1'
$script:MdUtf8 = [System.Text.UTF8Encoding]::new($false)

function Set-Leg([string]$leg) {
  if ($leg -notin @('ps1', 'sh')) { throw "unknown leg [$leg]" }
  $script:MdLeg = $leg
  # Resolved once here, on the real PATH: cases may replace PATH before Invoke-Leg runs.
  $script:MdBashBin = if ($leg -eq 'sh') { Get-BashBin } else { $null }
}
function Get-Leg { return $script:MdLeg }
# First PATH hit for a real executable, placed in $dir under its own name.
function Add-ToolStub([string]$name, [string]$dir) {
  $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $c) { return }
  $dest = Join-Path $dir (Split-Path -Leaf $c.Source)
  if ($IsWindows) { Copy-Item -LiteralPath $c.Source -Destination $dest }
  else { New-Item -ItemType SymbolicLink -Path $dest -Target $c.Source | Out-Null }
}

function Get-BashBin {
  if ($env:MD_BASH_BIN) { return $env:MD_BASH_BIN }
  if ($IsWindows) {
    # PATH `bash` on Windows is the WSL launcher; the twins ship for Git's bash.
    foreach ($c in @('C:/Program Files/Git/bin/bash.exe', 'C:/Program Files (x86)/Git/bin/bash.exe')) {
      if (Test-Path -LiteralPath $c) { return $c }
    }
  }
  # Absolute: .NET resolves a bare name against the child's PATH.
  $c = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  return $(if ($c) { $c.Source } else { 'bash' })
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
  $target = if ($script:MdLeg -eq 'sh') { "$Script.sh" } else { "$Script.ps1" }
  if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "FATAL: missing $target" }
  if ($script:MdLeg -eq 'sh') {
    return Invoke-Child -Exe $script:MdBashBin -Argv (@($target) + $Args) -Stdin $Stdin -Cwd $Cwd -Env $Env
  }
  return Invoke-InProcess -Path "$Script.ps1" -Argv $Args -Stdin $Stdin -Cwd $Cwd -Env $Env
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
    return Invoke-Child -Exe $script:MdBashBin -Argv (@("$Script.sh") + $Args) -Stdin $Stdin -Cwd $Cwd -Env $Env
  }
  return Invoke-Child -Exe (Get-Command pwsh).Source -Argv (@('-NoProfile', '-File', "$Script.ps1") + $Args) -Stdin $Stdin -Cwd $Cwd -Env $Env
}

function Invoke-InProcess {
  param([string]$Path, [string[]]$Argv, [string]$Stdin, [string]$Cwd, [hashtable]$Env)
  $oldIn = [Console]::In; $oldOut = [Console]::Out; $oldErr = [Console]::Error
  $sw = [System.IO.StringWriter]::new(); $se = [System.IO.StringWriter]::new()
  $oldCwd = (Get-Location).Path
  $oldProcCwd = [Environment]::CurrentDirectory
  $saved = @{}
  foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
  $rc = 0
  $pipe = ''
  try {
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    if ($Cwd) { Set-Location -LiteralPath $Cwd; [Environment]::CurrentDirectory = $Cwd }
    [Console]::SetIn([System.IO.StringReader]::new($Stdin))
    [Console]::SetOut($sw); [Console]::SetError($se)
    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $global:LASTEXITCODE = 0
    $pipe = (& $Path @Argv 6>&1 | Out-String)
    $rc = $global:LASTEXITCODE
  } catch {
    $se.Write($_.Exception.Message)
    $rc = 1
  } finally {
    [Console]::SetIn($oldIn); [Console]::SetOut($oldOut); [Console]::SetError($oldErr)
    Set-Location -LiteralPath $oldCwd
    [Environment]::CurrentDirectory = $oldProcCwd
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
  return @{ out = ($sw.ToString() + $pipe); err = $se.ToString(); rc = $rc }
}

function Invoke-Child {
  param([string]$Exe, [string[]]$Argv, [string]$Stdin, [string]$Cwd, [hashtable]$Env)
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $Exe
  foreach ($a in $Argv) { [void]$psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = if ($Cwd) { $Cwd } else { (Get-Location).Path }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardInputEncoding = $script:MdUtf8
  $psi.StandardOutputEncoding = $script:MdUtf8
  $psi.StandardErrorEncoding = $script:MdUtf8
  if ($IsWindows) { $psi.Environment['MSYS'] = 'noglob' }
  foreach ($k in $Env.Keys) { $psi.Environment[$k] = $Env[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($Stdin)
  $p.StandardInput.Close()
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{ out = $outTask.GetAwaiter().GetResult(); err = $errTask.GetAwaiter().GetResult(); rc = $p.ExitCode }
}
