<#
.SYNOPSIS
Render any Godot scene from fixed views (four obliques, front, side, top, plus
optional eye-level views) to PNGs for an agent to read, and probe where visible
geometry and collision disagree (see review_scene.gd).

.EXAMPLE
scripts/agent/review-scene.ps1 -Scene res://world/building_kit/samples/service_block.tscn
scripts/agent/review-scene.ps1 -Scene res://world/poi_kit/buildings/foo.tscn -Eye '0,1.6,6:0,1.6,0;0,1.6,-2:0,1.4,3' -Clay
#>
param(
	[Parameter(Mandatory = $true)][string]$Scene,
	[string]$Out,
	# Eye-level views as 'x,y,z:x,y,z' (position:target); separate several with ';'.
	[string]$Eye = '',
	[string]$Focus,
	[switch]$Clay,
	[switch]$NoGround,
	# Skip the visual-against-collision probe (on by default).
	[switch]$NoProbe,
	[string]$Size = '1280x720',
	# Method and arguments to call on the scene root before it enters the tree,
	# for site-configured POIs, e.g. 'configure,42,true'.
	[string]$Call = '',
	[string]$Project = ''
)
$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty inside param defaults on Windows PowerShell 5.1.
if (-not $Project) { $Project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
if (-not $Out) { $Out = Join-Path $Project ('.godot/scene-review/' + [IO.Path]::GetFileNameWithoutExtension($Scene)) }
New-Item -ItemType Directory -Force $Out | Out-Null
$log = Join-Path $Out 'godot.log'
$userArgs = @("--scene=$Scene", "--out=$Out", "--size=$Size")
foreach ($e in ($Eye -split ';' | Where-Object { $_.Trim() })) { $userArgs += "--eye=$($e.Trim())" }
if ($Focus) { $userArgs += "--focus=$Focus" }
if ($Call) { $userArgs += "--call=$Call" }
if ($Clay) { $userArgs += '--clay' }
if ($NoGround) { $userArgs += '--no-ground' }
if ($NoProbe) { $userArgs += '--no-probe' }
$godotArgs = @('--path', $Project, '--log-file', $log, '-s', 'res://scripts/agent/review_scene.gd', '--') + $userArgs
$process = Start-Process -FilePath 'godot' -ArgumentList $godotArgs -NoNewWindow -Wait -PassThru
$errors = @()
if (Test-Path $log) {
	$errors = Get-Content $log | Where-Object { $_ -match '(SCRIPT ERROR:|^ERROR:)' -and $_ -notmatch 'root certificate store' }
}
if ($process.ExitCode -ne 0 -or $errors.Count -gt 0) {
	$errors | ForEach-Object { Write-Host $_ }
	Write-Host "FAILED (exit $($process.ExitCode)); log: $log"
	exit 1
}
Get-ChildItem $Out -Filter '*.png' | ForEach-Object { $_.FullName }
$reportPath = Join-Path $Out 'review.json'
$report = Get-Content $reportPath -Raw | ConvertFrom-Json
if ($report.probe) {
	Write-Host ("Probe: {0} rays; visual only {1} hits in {2} places; collision only {3} hits in {4} places" -f `
		$report.probe.rays, $report.probe.visual_only.hits, $report.probe.visual_only.clusters,
		$report.probe.collision_only.hits, $report.probe.collision_only.clusters)
}
Write-Host "Report: $reportPath"
