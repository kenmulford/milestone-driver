#!/usr/bin/env pwsh
# milestone-driver — deterministic milestone version extractor (issue #158).
# stdin: JSON {title, description?}. stdout: normalized version or empty.
# When empty, stderr is "none" or "ambiguous:<v1>,<v2>,...". Fail-open, exit 0.
function Emit-None { [Console]::Error.Write('none'); exit 0 }

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { Emit-None }
try { $o = $raw | ConvertFrom-Json -ErrorAction Stop } catch { Emit-None }
$title = if ($null -ne $o.title) { [string]$o.title } else { '' }
$desc  = if ($null -ne $o.description) { [string]$o.description } else { '' }

$CAND = '[vV]?[0-9]+(\.[0-9]+){1,3}(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?'

function Normalize([string]$tok) {
  $t = $tok -replace '^[vV]', ''
  $core = $t; $suffix = ''
  $i = $t.IndexOfAny([char[]]@('-','+'))
  if ($i -ge 0) { $core = $t.Substring(0,$i); $suffix = $t.Substring($i) }
  $comps = $core -split '\.'
  if ($comps.Count -lt 2 -or $comps.Count -gt 4) { return $null }
  foreach ($c in $comps) { if ($c -notmatch '^(0|[1-9][0-9]*)$') { return $null } }
  if ($comps.Count -eq 2) { $core = "$core.0" }
  return "$core$suffix"
}
function PartCount([string]$tok) {
  $t = ($tok -replace '^[vV]','')
  $j = $t.IndexOfAny([char[]]@('-','+')); if ($j -ge 0) { $t = $t.Substring(0,$j) }
  return ($t -split '\.').Count
}
function Scan([string]$textIn, [bool]$anchor) {
  $text = $textIn.Trim(); $len = $text.Length; $acc = @()
  foreach ($m in [regex]::Matches($text, $CAND)) {
    $start = $m.Index; $end = $m.Index + $m.Length; $match = $m.Value
    if ($start -gt 0) { if ($text[$start-1] -match '[0-9A-Za-z.]') { continue } }
    # boundary after: reject digit, letter, or dot — symmetric with the before-check
    # (rejects a 5th component, a trailing digit, AND a trailing-letter token like
    # "1.2.3abc"). The suffix (-rc.1 / +build7) is part of the matched token, so the
    # after-char is evaluated PAST the suffix and pre-release/build metadata still pass.
    if ($end -lt $len) { if ($text[$end] -match '[0-9A-Za-z.]') { continue } }
    $norm = Normalize $match; if ($null -eq $norm) { continue }
    # 3-tier title anchoring (anchor=$true). WHY the tiers exist: bare numeric tokens
    # in a title are mostly NOT versions (dates "2024.06.19", section numbers
    # "section 1.2.3"), so the more ambiguous the shape, the stronger the position
    # it must occupy to be accepted.
    #   * bare 2-part (1.9)      -> whole-title only — too ambiguous mid-sentence.
    #   * bare 3/4-part (1.2.3)  -> title start OR end — rejects "section 1.2.3 rewrite".
    #   * v-prefixed (v1.2.3)    -> anywhere — the explicit "v" disambiguates it.
    # tests/extract-version.cases.tsv is the parity/regression contract that pins
    # the date / section-number false-positive cases; do NOT "simplify" these tiers
    # away — that regresses date_zeropad / bare_3part_mid / date_2part_decorated.
    if ($anchor) {
      $hasv = $match -match '^[vV]'
      if (-not $hasv) {
        $n = PartCount $match
        if ($n -eq 2) { if (-not ($start -eq 0 -and $end -eq $len)) { continue } }
        else { if (-not ($start -eq 0 -or $end -eq $len)) { continue } }
      }
    }
    $acc += $norm
  }
  return ,$acc
}

$tv = Scan $title $true
$distinct = @(); foreach ($v in $tv) { if ($distinct -notcontains $v) { $distinct += $v } }
if ($distinct.Count -eq 1) { [Console]::Out.Write($distinct[0]); exit 0 }
if ($distinct.Count -ge 2) { [Console]::Error.Write('ambiguous:' + ($distinct -join ',')); exit 0 }
$dv = Scan $desc $false
if ($dv.Count -ge 1) { [Console]::Out.Write($dv[0]); exit 0 }
Emit-None
