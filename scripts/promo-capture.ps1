<#
.SYNOPSIS
Opens the promo capture world. Pick and run shots from the in-game panel (F2).

.DESCRIPTION
Live takes are played by hand and recorded with OBS or another real-time recorder.
-Movie renders an unattended take (-Preview) with Godot Movie Maker, which runs
slower than real time and is therefore not playable by hand.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[BODRWTbodrwt][1-9]$')][string]$Shot = 'R2',
    [ValidateRange(0, 9)][int]$Variant = 0,
    [switch]$Preview,
    [switch]$Movie,
    [switch]$Exterior,
    [ValidateSet('Avi', 'Png')][string]$Format = 'Avi',
    [ValidateRange(1, 120)][int]$Fps = 60,
    [ValidatePattern('^[1-9][0-9]*x[1-9][0-9]*$')][string]$WindowResolution = '1920x1080',
    [switch]$Fullscreen,
    [string]$Godot = 'godot'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$executable = (Get-Command $Godot -ErrorAction Stop).Source
$console = Join-Path (Split-Path $executable) (([IO.Path]::GetFileNameWithoutExtension($executable)) + '_console.exe')
if (Test-Path -LiteralPath $console -PathType Leaf) { $executable = $console }
$id = $Shot.ToUpperInvariant()
$config = Join-Path $root "tests/playgrounds/promo/shots/$id.json"
if (!(Test-Path -LiteralPath $config -PathType Leaf)) { throw "Unknown shot $id" }
$shotSettings = Get-Content -Raw -LiteralPath $config | ConvertFrom-Json
$variantCount = if ($shotSettings.PSObject.Properties.Name -contains 'variants') { $shotSettings.variants.Count } else { 0 }
if ($Variant -gt $variantCount) { throw "Shot $id has variants 0 to $variantCount" }
if ($Movie -and !$Preview) {
    throw 'Movie Maker renders slower than real time, so a hand-played take turns into slow motion. Record live takes with OBS, or add -Preview for an unattended take.'
}
if ($Exterior -and !$Preview) { throw '-Exterior only applies to unattended takes. In a live take, use Follow in the panel (F2) or F4.' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$label = if ($Variant -gt 0) { "$id-v$Variant" } else { $id }
$take = Join-Path $root ".godot/promo-captures/$label-$stamp-$PID"
New-Item -ItemType Directory -Force -Path $take | Out-Null

$arguments = @('--path', $root, '--resolution', $WindowResolution, '--log-file', (Join-Path $take 'godot.log'))
$arguments += if ($Fullscreen) { '--fullscreen' } else { '--windowed' }
if ($Movie) {
    $output = Join-Path $take ("take." + $Format.ToLowerInvariant())
    $arguments += @('--write-movie', $output, '--fixed-fps', $Fps)
    Write-Host "Recording to $output (the take starts at the frame in take.json)"
}
$arguments += @('res://tests/playgrounds/promo/promo_world.tscn', '--', "--shot=$id", "--variant=$Variant", "--take-dir=$take", "--capture-fps=$Fps")
if ($Preview) { $arguments += '--preview' }
if ($Exterior) { $arguments += '--exterior' }
Write-Host "Take files: $take"
if (!$Preview) { Write-Host 'Press F2 in the game for the shot list and controls.' }
& $executable @arguments
exit $LASTEXITCODE
