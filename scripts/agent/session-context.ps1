# Prints live repository facts for coding agents. Read-only; safe to run any time.
# Claude Code runs it as a SessionStart hook; other agents run it manually.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Get-Git([string[]]$Arguments) { (& git -C $root -c core.quotepath=false @Arguments 2>$null | Out-String).Trim() }
function Get-Constant([string]$File, [string]$Pattern) {
    $path = Join-Path $root $File
    if (-not (Test-Path -LiteralPath $path)) { return '?' }
    $match = Select-String -LiteralPath $path -Pattern $Pattern | Select-Object -First 1
    if ($match) { $match.Matches[0].Groups[1].Value } else { '?' }
}

$lines = [Collections.Generic.List[string]]::new()
$lines.Add('ApocalypseRV live context (read from the repository; prefer it over prose in docs)')

$branch = Get-Git @('branch', '--show-current')
$head = Get-Git @('rev-parse', '--short=8', 'HEAD')
$dirty = @((Get-Git @('status', '--porcelain')) -split "`n" | Where-Object { $_ }).Count
$counts = (Get-Git @('rev-list', '--left-right', '--count', 'origin/main...HEAD')) -split '\s+'
$relation = if ($counts.Count -eq 2) { "$($counts[1]) ahead, $($counts[0]) behind origin/main (as of last fetch)" } else { 'no origin/main' }
$lines.Add("- Git: branch $branch at $head; $relation; $dirty uncommitted paths")

$generation = Get-Constant 'world/terrain/world_profile.gd' 'generation_version\s*:\s*int\s*=\s*(\d+)'
$checkpoint = Get-Constant 'rv/checkpoint.gd' '^const VERSION\s*:?=\s*(\d+)'
$snapshot = Get-Constant 'rv/vehicle_snapshot.gd' '^const VERSION\s*:?=\s*(\d+)'
$godot = (Get-Content -LiteralPath (Join-Path $root '.godot-version') -Raw -ErrorAction SilentlyContinue).Trim()
$lines.Add("- Versions in code: world generation v$generation, Checkpoint v$checkpoint, VehicleSnapshot v$snapshot; Godot $godot pinned")

$tests = @(Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter 'test_*.gd' -File -ErrorAction SilentlyContinue)
$lines.Add("- Automated checks: $($tests.Count) top-level tests/test_*.gd plus main-scene smoke")

$logRoot = Join-Path $root '.godot/test-logs'
$lastFull = Get-ChildItem -LiteralPath $logRoot -Directory -Filter '*-all-*' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'results.json') } |
    Sort-Object Name -Descending | Select-Object -First 1
if ($lastFull) {
    try {
        $report = Get-Content -LiteralPath (Join-Path $lastFull.FullName 'results.json') -Raw | ConvertFrom-Json
        $ran = @($report.results | Where-Object { $_.name -ne 'import' })
        $failed = @($ran | Where-Object { $_.status -ne 'PASS' } | ForEach-Object { "$($_.name) ($($_.status))" })
        $notRun = @($report.selected.Name | Where-Object { $_ -notin @($report.results.name) })
        $commit = "$($report.metadata.commit)".Substring(0, [Math]::Min(8, "$($report.metadata.commit)".Length))
        $stamp = $lastFull.Name.Substring(0, 15)
        $state = if ($commit -eq $head -and -not $report.metadata.working_tree) { 'this HEAD, clean tree' } elseif ($commit -eq $head) { 'this HEAD, dirty tree' } else { "commit $commit" }
        $summary = "$(@($ran | Where-Object status -eq 'PASS').Count)/$(@($report.selected).Count) passed"
        if ($failed.Count) { $summary += "; failed: $($failed -join ', ')" }
        if ($notRun.Count) { $summary += "; not run: $($notRun -join ', ')" }
        $lines.Add("- Last full local test run ($stamp, $state): $summary")
    } catch { $lines.Add("- Last full local test run: unreadable report in $($lastFull.Name)") }
} else {
    $lines.Add('- Last full local test run: none recorded in .godot/test-logs')
}

$skillCheck = & (Join-Path $PSScriptRoot 'sync-skills.ps1') -Check 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { $lines.Add("- WARNING: .claude/skills is out of sync; run scripts/agent/sync-skills.ps1. $($skillCheck.Trim())") }

$lines -join "`n"
