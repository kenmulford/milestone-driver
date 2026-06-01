#!/usr/bin/env pwsh
# milestone-driver — no-bom gate (Claude PreToolUse: Write|Edit|MultiEdit).
# Denies writes whose content begins with the UTF-8 BOM (EF BB BF / U+FEFF).
# Deny: exit 2 + stderr. Escape: CLAUDE_HOOK_DISABLE_NO_BOM=1. Fail-open.

if ($env:CLAUDE_HOOK_DISABLE_NO_BOM -eq '1') { exit 0 }

# The hook payload is UTF-8 (Claude Code encodes it as such). Set the console
# input encoding to UTF-8 before reading so that raw multi-byte sequences
# (including the BOM bytes EF BB BF) are decoded correctly. The Windows default
# is OEM (CP437) which would corrupt non-ASCII bytes before we can inspect them.
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $hook = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$BOM = [char]0xFEFF

function Test-LeadingBom([string]$s) {
    return ($s.Length -gt 0 -and $s[0] -eq $BOM)
}

$tool = $hook.tool_name

switch ($tool) {
    'Write' {
        $content = $hook.tool_input.content
        if ($content -and (Test-LeadingBom $content)) {
            [Console]::Error.WriteLine("milestone-driver: no-bom gate — content begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override.")
            exit 2
        }
    }
    'Edit' {
        $ns = $hook.tool_input.new_string
        if ($ns -and (Test-LeadingBom $ns)) {
            [Console]::Error.WriteLine("milestone-driver: no-bom gate — new_string begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override.")
            exit 2
        }
    }
    'MultiEdit' {
        $edits = $hook.tool_input.edits
        if (-not $edits) { exit 0 }
        $i = 0
        foreach ($edit in $edits) {
            $ns = $edit.new_string
            if ($ns -and (Test-LeadingBom $ns)) {
                [Console]::Error.WriteLine("milestone-driver: no-bom gate — edits[$i].new_string begins with the UTF-8 BOM (U+FEFF). Write BOM-less UTF-8 instead, or set CLAUDE_HOOK_DISABLE_NO_BOM=1 to override.")
                exit 2
            }
            $i++
        }
    }
}

exit 0
