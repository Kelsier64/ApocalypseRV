# Checks files about to be committed for intermediate outputs and oversized binaries.
# Manual use: run after staging; exits 1 when something must not be committed.
# -Hook: Claude Code PreToolUse payload on stdin; inspects only `git commit`
# commands, including files staged earlier in the same command.
[CmdletBinding()]
param([switch]$Hook)
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
function Get-GitList([string[]]$Arguments) { @(& git -C $root -c core.quotepath=false @Arguments 2>$null | Where-Object { $_ }) }

$files = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$newFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($Hook) {
    try { $command = "$(([Console]::In.ReadToEnd().TrimStart([char]0xFEFF) | ConvertFrom-Json).tool_input.command)" } catch { exit 0 }
    if ($command -notmatch '\bgit\b[^\r\n;&|]*\bcommit\b') { exit 0 }
    foreach ($add in [regex]::Matches($command, '\bgit\s+add\b([^\r\n;&|]*)')) {
        $words = @($add.Groups[1].Value.Trim() -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Trim('"', "'") })
        $specs = @($words | Where-Object { $_ -notmatch '^-' })
        if ($words -contains '-A' -or $words -contains '--all' -or $specs -contains '.') { $specs = @() }
        elseif ($specs.Count -eq 0) { continue }
        foreach ($file in Get-GitList (@('ls-files', '--others', '--exclude-standard', '--') + $specs)) { [void]$files.Add($file); [void]$newFiles.Add($file) }
        foreach ($file in Get-GitList (@('ls-files', '--modified', '--') + $specs)) { [void]$files.Add($file) }
    }
    if ($command -match '\bcommit\b[^\r\n;&|]*\s(--all|-[a-zA-Z]*a[a-zA-Z]*)(\s|$)') {
        foreach ($file in Get-GitList @('diff', '--name-only', '--diff-filter=ACMR')) { [void]$files.Add($file) }
    }
}
foreach ($file in Get-GitList @('diff', '--cached', '--name-only', '--diff-filter=ACMR')) { [void]$files.Add($file) }
foreach ($file in Get-GitList @('diff', '--cached', '--name-only', '--diff-filter=A')) { [void]$newFiles.Add($file) }

$blocked = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()
foreach ($file in $files) {
    if ($file -match '^\.godot/') { $blocked.Add("$file (Godot cache)"); continue }
    if ($file -match '\.(blend\d+|log|zip|7z|rar|tmp|bak|orig)$') { $blocked.Add("$file (backup, log, or archive)"); continue }
    $item = Get-Item -LiteralPath (Join-Path $root $file) -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer) { continue }
    $megabytes = [Math]::Round($item.Length / 1MB, 1)
    if ($megabytes -gt 95) { $blocked.Add("$file ($megabytes MB, over GitHub's 100 MB limit)") }
    elseif ($megabytes -gt 25) { $warnings.Add("$file ($megabytes MB)") }
}
$evidence = @($newFiles | Where-Object { $_ -match '^docs/.*\.(png|jpe?g|webp|gif|mp4)$' })
if ($evidence.Count -gt 6) { $warnings.Add("$($evidence.Count) new images under docs/ (keep a few representative ones; leave the rest in .godot/)") }

$message = ''
if ($blocked.Count) { $message += "Must not be committed (keep it in .godot/ or another ignored path, then unstage it): $($blocked -join '; '). " }
if ($warnings.Count) { $message += "Review before committing: $($warnings -join '; ')." }
if ($Hook) {
    if (-not $message) { exit 0 }
    $decision = if ($blocked.Count) { 'deny' } else { 'ask' }
    @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = $decision; permissionDecisionReason = "check-staged: $message" } } |
        ConvertTo-Json -Compress -Depth 4
    exit 0
}
if ($message) { Write-Output $message } else { Write-Output "check-staged: $($files.Count) files OK." }
exit [int]($blocked.Count -gt 0)
