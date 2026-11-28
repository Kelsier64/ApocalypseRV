<#
.SYNOPSIS
Trims the uninterrupted W4 weather drive between its start and end markers.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Take,
    [string]$OutputDirectory = '.godot/promo-weather',
    [string]$Ffmpeg = 'ffmpeg'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$encoder = (Get-Command $Ffmpeg -CommandType Application).Source
$sampleRate = 48000
$shot = Get-Content -Raw -LiteralPath (Join-Path $root 'tests/playgrounds/promo/shots/W4.json') | ConvertFrom-Json
$meta = Get-Content -Raw -LiteralPath (Join-Path $Take 'take.json') | ConvertFrom-Json
$fps = [int]$meta.fps
if ($meta.shot -ne 'W4' -or $meta.variant -ne 0 -or $fps -lt 1 -or $fps -gt 120 -or
    $meta.seed -ne $shot.seed -or $meta.distance -ne $shot.distance) {
    throw "Expected a W4 drive at seed $($shot.seed), $($shot.distance) m in $Take."
}

$start = $meta.markers | Where-Object name -EQ 'weather_start' | Select-Object -First 1
$end = $meta.markers | Where-Object name -EQ 'weather_end' | Select-Object -First 1
$startCue = $shot.timeline | Where-Object name -EQ 'weather_start' | Select-Object -First 1
$endCue = $shot.timeline | Where-Object name -EQ 'weather_end' | Select-Object -First 1
$duration = [double]$endCue.at - [double]$startCue.at
$frameCount = [int][Math]::Round($duration * $fps)
if ($null -eq $start.frame -or $null -eq $end.frame -or $start.frame -lt 0 -or
    [Math]::Abs(($end.frame - $start.frame) - $frameCount) -gt 1) {
    throw "The W4 drive in $Take is missing the expected start and end markers."
}

$first = [int]$start.frame + 1
$last = $first + $frameCount
$firstSample = [int][Math]::Round($first * $sampleRate / $fps)
$lastSample = [int][Math]::Round($last * $sampleRate / $fps)
$blink = $shot.timeline | Where-Object do -EQ 'eyes' | Select-Object -First 1
$fadeAt = ([double]$blink.at - [double]$startCue.at).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
$source = (Resolve-Path -LiteralPath (Join-Path $Take 'take.avi')).Path
$picture = "trim=start_frame=${first}:end_frame=${last},setpts=PTS-STARTPTS,scale=out_range=tv,format=yuv420p"
$sound = "aresample=${sampleRate},atrim=start_sample=${firstSample}:end_sample=${lastSample},asetpts=PTS-STARTPTS,highpass=f=55,lowpass=f=4000,volume=8dB,afade=t=in:d=0.22,afade=t=out:st=${fadeAt}:d=0.44"

$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$movie = Join-Path $output 'promo-weather-review.mp4'
& $encoder -nostdin -y -hide_banner -loglevel warning -i $source -vf $picture -af $sound `
    -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k -movflags +faststart $movie
if ($LASTEXITCODE -ne 0) { throw "FFmpeg exited with code $LASTEXITCODE." }
Get-Item -LiteralPath $movie
