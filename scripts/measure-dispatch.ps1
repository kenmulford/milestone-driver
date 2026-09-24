#!/usr/bin/env pwsh
# milestone-driver - dispatch step and first-edit metrics from one subagent
# JSONL transcript (issue #693).
# Usage: measure-dispatch.ps1 <transcript>
# stdout: ONE compact JSON line, keys in order
#   {"steps":n,"stepsBeforeFirstEdit":n,"minutesToFirstEdit":m,"minutes":m}
#   With no edit call (Edit, Write, or file-writing Bash), only
#   {"steps":n,"minutes":m}. No transcript text ever reaches stdout.
# Transcript shape and every rule below mirror the .sh twin, which states them.
# JsonDocument, not ConvertFrom-Json: the latter turns ISO-8601 strings into
#   local DateTime values and loses the jq leg's exact type checks.
# ParseExact takes only the one form jq's fromdate accepts (%Y-%m-%dT%H:%M:%SZ),
#   so a timestamp one leg rejects the other rejects too.
# [Math]::Round defaults to banker's rounding; AwayFromZero matches jq's round.
# Fail-closed, mirroring scripts/read-doc-section.ps1: a missing/unreadable file
#   writes one stderr line, exits NONZERO, and prints nothing on stdout.
# Exit codes: 0 ok · 1 unreadable file / timestamp parse failure · 2 bad usage.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Err([string]$msg) { [Console]::Error.WriteLine($msg) }

# Mirrors scripts/write-cost-record.ps1 (function Fmt-Num): jq prints a whole
# number without ".0".
function Fmt-Num([double]$d) {
  if ([Math]::Floor($d) -eq $d) { return ([long]$d).ToString([cultureinfo]::InvariantCulture) }
  return $d.ToString([cultureinfo]::InvariantCulture)
}

function Test-BashEdit([System.Text.Json.JsonElement]$b) {
  $in = [System.Text.Json.JsonElement]::new(); $cmd = [System.Text.Json.JsonElement]::new()
  if (-not ($b.TryGetProperty('input', [ref]$in) -and $in.ValueKind -eq 'Object')) { return $false }
  if (-not ($in.TryGetProperty('command', [ref]$cmd) -and $cmd.ValueKind -eq 'String')) { return $false }
  $s = $cmd.GetString()
  return ($s.Contains('sed -i') -or $s.Contains('perl -i') -or
    [regex]::IsMatch($s, '(^|[^A-Za-z0-9_-])tee[ \t]+(?!/dev/null)') -or
    [regex]::IsMatch($s, '>>?[ \t]*(?!/dev/null)[^ \t>&]'))
}

function Mins($a, $b) {
  if ($null -eq $a -or $null -eq $b) { return 0 }
  return [Math]::Round([double]($b - $a) / 6, [MidpointRounding]::AwayFromZero) / 10
}

if ($args.Count -ne 1) {
  Err 'usage: measure-dispatch.ps1 <transcript>'
  exit 2
}
$file = $args[0]

if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
  Err "measure-dispatch: file not found or not readable: $file"
  exit 1
}
try {
  $lines = @(Get-Content -LiteralPath $file -ErrorAction Stop)
} catch {
  Err "measure-dispatch: file not found or not readable: $file"
  exit 1
}

$steps = 0; $before = $null; $t0 = $null; $tl = $null; $tf = $null
try {
  foreach ($line in $lines) {
    try { $e = ([System.Text.Json.JsonDocument]::Parse($line)).RootElement } catch { continue }
    if ($e.ValueKind -ne 'Object') { continue }

    $p = [System.Text.Json.JsonElement]::new()
    if ($e.TryGetProperty('timestamp', [ref]$p) -and $p.ValueKind -eq 'String') {
      $s = [regex]::new('\.[0-9]+').Replace($p.GetString(), '', 1)
      $t = [datetimeoffset]::ParseExact($s, "yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUnixTimeSeconds()
      if ($null -eq $t0) { $t0 = $t }
      $tl = $t
    }

    if (-not ($e.TryGetProperty('type', [ref]$p) -and $p.ValueKind -eq 'String' -and $p.GetString() -ceq 'assistant')) { continue }
    if (-not ($e.TryGetProperty('message', [ref]$p) -and $p.ValueKind -eq 'Object')) { continue }
    $c = [System.Text.Json.JsonElement]::new()
    if (-not ($p.TryGetProperty('content', [ref]$c) -and $c.ValueKind -eq 'Array')) { continue }
    foreach ($b in $c.EnumerateArray()) {
      if ($b.ValueKind -ne 'Object') { continue }
      $q = [System.Text.Json.JsonElement]::new()
      if (-not ($b.TryGetProperty('type', [ref]$q) -and $q.ValueKind -eq 'String' -and $q.GetString() -ceq 'tool_use')) { continue }
      if ($null -eq $before -and $b.TryGetProperty('name', [ref]$q) -and $q.ValueKind -eq 'String' -and
          ($q.GetString() -ceq 'Edit' -or $q.GetString() -ceq 'Write' -or
           ($q.GetString() -ceq 'Bash' -and (Test-BashEdit $b)))) {
        $before = $steps; $tf = $tl
      }
      $steps++
    }
  }
} catch {
  Err "measure-dispatch: could not parse timestamps in: $file"
  exit 1
}

$json = '{"steps":' + $steps
if ($null -ne $before) {
  $json += ',"stepsBeforeFirstEdit":' + $before + ',"minutesToFirstEdit":' + (Fmt-Num (Mins $t0 $tf))
}
$json += ',"minutes":' + (Fmt-Num (Mins $t0 $tl)) + '}'
# LF, not the host newline: byte parity with the .sh twin.
[Console]::Out.Write($json + "`n")
