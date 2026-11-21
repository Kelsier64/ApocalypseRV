<#
.SYNOPSIS
Render any Godot scene from fixed views (four obliques, front, side, top, plus
optional eye-level views) to PNGs for an agent to read.

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
	[string]$Size = '1280x720',
	[string]$Project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
)
$ErrorActionPreference = 'Stop'
if (-not $Out) { $Out = Join-Path $Project ('.godot/scene-review/' + [IO.Path]::GetFileNameWithoutExtension($Scene)) }
New-Item -ItemType Directory -Force $Out | Out-Null
$log = Join-Path $Out 'godot.log'
$userArgs = @("--scene=$Scene", "--out=$Out", "--size=$Size")
foreach ($e in ($Eye -split ';' | Where-Object { $_.Trim() })) { $userArgs += "--eye=$($e.Trim())" }
if ($Focus) { $userArgs += "--focus=$Focus" }
if ($Clay) { $userArgs += '--clay' }
if ($NoGround) { $userArgs += '--no-ground' }
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
Write-Host "Report: $(Join-Path $Out 'review.json')"
