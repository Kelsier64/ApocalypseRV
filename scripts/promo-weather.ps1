<#
.SYNOPSIS
Edits four W4 takes into the trailer's wordless weather montage.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateCount(4, 4)][string[]]$Takes,
    [string]$OutputDirectory = '.godot/promo-weather',
    [string]$Ffmpeg = 'ffmpeg'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'promo-eyelids.ps1')
$root = Split-Path $PSScriptRoot -Parent
$encoder = (Get-Command $Ffmpeg -CommandType Application).Source
$fps = 60
$sampleRate = 48000
$samplesPerFrame = $sampleRate / $fps
$cuts = @(0, 180, 360, 525, 720)
$gainDb = @(12, 10, 0, 15)
$overlap = 3840 # samples on each side of an audio cut
$shot = Get-Content -Raw -LiteralPath (Join-Path $root 'tests/playgrounds/promo/shots/W4.json') | ConvertFrom-Json
$inputs = @()
$filters = @()

for ($index = 0; $index -lt $Takes.Count; $index++) {
    $directory = $Takes[$index]
    $take = Get-Content -Raw -LiteralPath (Join-Path $directory 'take.json') | ConvertFrom-Json
    if ($take.shot -ne 'W4' -or $take.variant -ne $index -or $take.fps -ne $fps -or
        $take.seed -ne $shot.seed -or $take.distance -ne $shot.distance -or
        $null -eq $take.start_frame -or $take.start_frame -lt 0) {
        throw "Expected W4 variant $index, seed $($shot.seed), at $($shot.distance) m and $fps fps in $directory."
    }
    $inputs += @('-i', (Resolve-Path -LiteralPath (Join-Path $directory 'take.avi')).Path)
    # All four takes share the same rail, trimmed at the same position on each cut.
    $first = [int]$take.start_frame + $cuts[$index] + 1
    $last = [int]$take.start_frame + $cuts[$index + 1] + 1
    $filters += "[${index}:v]trim=start_frame=${first}:end_frame=${last},setpts=PTS-STARTPTS,scale=out_range=tv,format=yuv420p[v$index]"

    $firstSample = [int]($first * $samplesPerFrame)
    $lastSample = [int]($last * $samplesPerFrame)
    if ($index -gt 0) { $firstSample -= $overlap }
    if ($index -lt $Takes.Count - 1) { $lastSample += $overlap }
    $filters += "[${index}:a]aresample=${sampleRate},atrim=start_sample=${firstSample}:end_sample=${lastSample},asetpts=PTS-STARTPTS,volume=$($gainDb[$index])dB[a$index]"
}

$blink = Get-PromoEyelidsFilter '11.1' '0.38'
$crossfade = "acrossfade=ns=$($overlap * 2)"
$filters += @(
    "[v0][v1][v2][v3]concat=n=4:v=1:a=0,$blink[picture]"
    "[a0][a1]$crossfade[m01]"
    "[m01][a2]$crossfade[m012]"
    "[m012][a3]$crossfade,highpass=f=55,lowpass=f=3300,afade=t=in:d=0.22,afade=t=out:st=11.1:d=0.44[sound]"
)

$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$movie = Join-Path $output 'promo-weather-review.mp4'
& $encoder -nostdin -y -hide_banner -loglevel warning @inputs `
    -filter_complex_threads 2 -filter_complex ($filters -join ';') -map '[picture]' -map '[sound]' `
    -t ($cuts[-1] / $fps) -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k -movflags +faststart $movie
if ($LASTEXITCODE -ne 0) { throw "FFmpeg exited with code $LASTEXITCODE." }
Get-Item -LiteralPath $movie
