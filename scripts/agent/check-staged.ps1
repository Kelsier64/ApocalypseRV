# Checks files about to be committed for intermediate outputs, oversized binaries,
# new world-space text nodes, and docs that break links or the docs/ layout.
# Manual use: run after staging; exits 1 when something must not be committed.
# -Hook: PreToolUse payload on stdin; inspects only `git commit`
# commands, including files staged earlier in the same command.
# Checks the repository the commit lands in: a worktree named by `git -C`, a leading
# `cd`/`Set-Location`, or the hook's working directory (manual use: the current one).
[CmdletBinding()]
param([switch]$Hook, [switch]$Codex)
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
function Resolve-Repo([string]$Directory, [string]$Base) {
    if (-not $Directory) { return $null }
    if ($Base -and -not [IO.Path]::IsPathRooted($Directory)) { $Directory = Join-Path $Base $Directory }
    $top = & git -C $Directory rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $top) { return "$top".Trim() }
    return $null
}
$quotedPath = '(?:"([^"]+)"|''([^'']+)''|([^\s;&|]+))'
$command = ''
$workDir = (Get-Location).Path
if ($Hook) {
    try { $payload = [Console]::In.ReadToEnd().TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { exit 0 }
    $command = "$($payload.tool_input.command)"
    if ($command -notmatch '\bgit\b[^\r\n;&|]*\bcommit\b') { exit 0 }
    if ($payload.cwd) { $workDir = "$($payload.cwd)" }
}
$target = $null
if ($command -match "\bgit\s+-C\s+$quotedPath") { $target = ($Matches[1], $Matches[2], $Matches[3] | Where-Object { $_ } | Select-Object -First 1) }
elseif ($command -match "^\s*(?:cd|Set-Location|sl|pushd|Push-Location)\s+(?:-LiteralPath\s+|-Path\s+)?$quotedPath") { $target = ($Matches[1], $Matches[2], $Matches[3] | Where-Object { $_ } | Select-Object -First 1) }
$root = Resolve-Repo $target $workDir
if (-not $root) { $root = Resolve-Repo $workDir $null }
if (-not $root) { $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
function Get-GitList([string[]]$Arguments) { @(& git -C $root -c core.quotepath=false @Arguments 2>$null | Where-Object { $_ }) }

$files = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$newFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($Hook) {
    foreach ($add in [regex]::Matches($command, "\bgit\s+(?:-C\s+$quotedPath\s+)?add\b(?<args>[^\r\n;&|]*)")) {
        $words = @($add.Groups['args'].Value.Trim() -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Trim('"', "'") })
        $specs = @($words | Where-Object { $_ -notmatch '^-' })
        if ($words -contains '-A' -or $words -contains '--all' -or $specs -contains '.') { $specs = @() }
        elseif ($specs.Count -eq 0) { continue }
        foreach ($file in Get-GitList (@('ls-files', '--others', '--exclude-standard', '--') + $specs)) { [void]$files.Add($file); [void]$newFiles.Add($file) }
        foreach ($file in Get-GitList (@('ls-files', '--modified', '--') + $specs)) { [void]$files.Add($file) }
    }
    # `git commit ... -- <paths>` commits those paths without staging them first.
    if ($command -match '\bcommit\b[^\r\n;&|]*\s--\s+([^\r\n;&|]+)') {
        $specs = @($Matches[1].Trim() -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Trim('"', "'") })
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
# Catch world-space text nodes in the pending commit, including shell-made edits.
foreach ($file in $files) {
    if ($file -notmatch '\.(gd|tscn|tres|scn)$' -or $file -match '^(tests|art_source|docs|scripts|\.claude)/') { continue }
    $added = if ($newFiles.Contains($file)) { @(Get-Content -LiteralPath (Join-Path $root $file) -ErrorAction SilentlyContinue) }
        else { @(Get-GitList @('diff', 'HEAD', '--unified=0', '--', $file) | Where-Object { $_ -match '^\+(?!\+\+)' }) }
    if (($added -join "`n") -cmatch '\b(Label3D|TextMesh)\b') { $blocked.Add("$file (adds Label3D/TextMesh; world text must be texture, decal or device-screen art)") }
}
$evidence = @($newFiles | Where-Object { $_ -match '^docs/.*\.(png|jpe?g|webp|gif|mp4)$' })
if ($evidence.Count -gt 6) { $warnings.Add("$($evidence.Count) new images under docs/ (keep a few representative ones; leave the rest in .godot/)") }
# Docs in the pending commit must keep their links and the docs/ layout (docs-maintenance skill).
$docFiles = @($files | Where-Object { $_ -match '\.md$' -or $_ -match '^docs/' })
if ($docFiles.Count) {
    $docProblems = @(& (Join-Path $PSScriptRoot 'check-docs.ps1') -Root $root @docFiles | Where-Object { $_ -match '^(BROKEN|MISPLACED)' })
    if ($docProblems.Count) { $warnings.Add("docs check: $($docProblems -join ' | ')") }
}

$message = ''
if ($blocked.Count) { $message += "Must not be committed (fix it, or keep it in .godot/ or another ignored path and unstage it): $($blocked -join '; '). " }
if ($warnings.Count) { $message += "Review before committing: $($warnings -join '; ')." }
if ($Hook) {
    if (-not $message) { exit 0 }
    if ($Codex -and -not $blocked.Count) {
        @{ systemMessage = "check-staged: $message" } | ConvertTo-Json -Compress
        exit 0
    }
    $decision = if ($blocked.Count) { 'deny' } else { 'ask' }
    @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = $decision; permissionDecisionReason = "check-staged: $message" } } |
        ConvertTo-Json -Compress -Depth 4
    exit 0
}
if ($message) { Write-Output $message } else { Write-Output "check-staged: $($files.Count) files OK." }
exit [int]($blocked.Count -gt 0)
