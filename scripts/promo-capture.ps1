[CmdletBinding()]
param(
    [ValidatePattern('^[BODRW][1-6]$')][string]$Shot = 'R2',
    [ValidateRange(0, 9)][int]$Variant = 0,
    [switch]$Movie,
    [switch]$Preview,
    [switch]$Exterior,
    [ValidateSet('Avi', 'Png')][string]$Format = 'Avi',
    [ValidateRange(1, 120)][int]$Fps = 30,
    [ValidatePattern('^[1-9][0-9]*x[1-9][0-9]*$')][string]$WindowResolution = '1280x720',
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
if ($Variant -gt $shotSettings.variants.Count) { throw "Unknown variant $Variant for $id" }
if ($Exterior -and (!$Preview -or $id -notin @('O2', 'O4', 'D1', 'D2', 'D3'))) {
    throw '-Exterior requires -Preview and a driving shot (O2, O4, D1, D2 or D3)'
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$label = if ($Variant -gt 0) { "$id-v$Variant" } else { $id }
$take = Join-Path $root ".godot/promo-captures/$label-$stamp-$PID"
New-Item -ItemType Directory -Force -Path $take | Out-Null

$arguments = @('--path', $root, '--windowed', '--resolution', $WindowResolution, '--log-file', (Join-Path $take 'godot.log'))
if ($Movie) {
    $output = Join-Path $take ("take." + $Format.ToLowerInvariant())
    $arguments += @('--write-movie', $output, '--fixed-fps', $Fps)
    Write-Host "Recording to $output"
}
$arguments += @('res://tests/playgrounds/promo/promo_world.tscn', '--', "--shot=$id", "--variant=$Variant")
if ($Preview) { $arguments += '--preview' }
if ($Exterior) { $arguments += '--exterior' }
Write-Host "Take files: $take"
& $executable @arguments
exit $LASTEXITCODE
