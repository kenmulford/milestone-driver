# Shared deny for every gate. Codex ignores exit 2 and blocks only on a stdout
# permissionDecision, so a payload carrying turn_id (Codex) gets that JSON and
# exit 0. Claude Code keeps exit 2 + stderr.
# Usage: Invoke-HookDeny $hook "milestone-driver: <reason>"
function Invoke-HookDeny($Hook, [string]$Reason) {
    if ($Hook.turn_id) {
        $deny = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $Reason } }
        # ASCII-only: Codex runs hooks without a console, where stdout is the OEM code page.
        [Console]::Out.WriteLine(($deny | ConvertTo-Json -Compress -Depth 3 -EscapeHandling EscapeNonAscii))
        exit 0
    }
    [Console]::Error.WriteLine($Reason)
    exit 2
}
