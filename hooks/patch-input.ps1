function Read-CodexPatch([string]$Command) {
    $paths = [Collections.Generic.List[string]]::new()
    $active = $false; $mode = ''; $firstAdd = $false; $addedBlock = $false; $hasBom = $false
    foreach ($line in ($Command -split "`n")) {
        $line = $line.TrimEnd("`r")
        if (-not $active) {
            if ($line -eq '*** Begin Patch') { $active = $true }
            continue
        }
        # Headers match trimmed, as Codex's parser trims them; content lines stay raw.
        $t = $line.Trim()
        if ($t -eq '*** End Patch') { break }
        if ($t -cmatch '^\*\*\* (Add|Update|Delete) File: (.+)$') {
            $mode = $Matches[1]; $paths.Add($Matches[2]); $firstAdd = $true; $addedBlock = $false
        } elseif ($t -cmatch '^\*\*\* Move to: (.+)$') {
            if ($mode -eq 'Update') { $paths.Add($Matches[1]) }
            $paths.Add($Matches[1]); $addedBlock = $false
        } elseif ($line.StartsWith('+') -and $mode -in @('Add', 'Update')) {
            $text = $line.Substring(1)
            if ((($mode -eq 'Add' -and $firstAdd) -or ($mode -eq 'Update' -and -not $addedBlock)) -and $text.Length -gt 0 -and $text[0] -eq [char]0xfeff) { $hasBom = $true }
            $firstAdd = $false; $addedBlock = $true
        } else {
            $addedBlock = $false
        }
    }
    return @{ Paths = $paths.ToArray(); HasBom = $hasBom }
}

function ConvertTo-HookPath([string]$Path, [string]$BasePath) {
    $pathText = $Path.Replace('\', '/')
    if ($pathText -notmatch '^(/|[A-Za-z]:/)') { $pathText = "$BasePath/$pathText" }
    $prefix = ''
    if ($pathText -match '^[A-Za-z]:/') { $prefix = $pathText.Substring(0, 3); $pathText = $pathText.Substring(3) }
    elseif ($pathText.StartsWith('//')) { $prefix = '//'; $pathText = $pathText.Substring(2) }
    elseif ($pathText.StartsWith('/')) { $prefix = '/'; $pathText = $pathText.Substring(1) }
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($part in ($pathText -split '/')) {
        if (-not $part -or $part -eq '.') { continue }
        if ($part -eq '..') { if ($parts.Count) { $parts.RemoveAt($parts.Count - 1) }; continue }
        $parts.Add($part)
    }
    return $prefix + ($parts -join '/')
}
