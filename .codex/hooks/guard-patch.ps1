# Check added lines in game files from the apply_patch PreToolUse payload.
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$inputData = [Console]::In.ReadToEnd().TrimStart([char]0xFEFF) | ConvertFrom-Json
$root = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -replace '\\', '/'
$cwd = if ($inputData.cwd) { $inputData.cwd } else { (Get-Location).Path }

$gameFile = $false
foreach ($line in ("$($inputData.tool_input.command)" -split '\r?\n')) {
    if ($line -match '^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$') {
        $path = $Matches[1]
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $cwd $path }
        $path = [IO.Path]::GetFullPath($path) -replace '\\', '/'
        $gameFile = $false
        if ($path.StartsWith("$root/", [StringComparison]::OrdinalIgnoreCase)) {
            $relative = $path.Substring($root.Length + 1)
            $gameFile = $relative -match '\.(gd|tscn|tres|scn)$' -and
                $relative -notmatch '^(tests|art_source|docs|scripts|\.[^/]+)/'
        }
        continue
    }
    if ($gameFile -and $line.StartsWith('+') -and $line -cmatch '\b(Label3D|TextMesh)\b') {
        @{ hookSpecificOutput = @{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = "The patch adds Label3D or TextMesh to $relative. Use screen-space UI for prompts and status, or a texture, decal, or device screen for essential in-fiction text."
        } } | ConvertTo-Json -Compress -Depth 3
        exit 0
    }
}
