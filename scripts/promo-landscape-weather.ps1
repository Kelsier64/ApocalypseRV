<#
.SYNOPSIS
Edits the five W5 drives into one trailer scene.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateCount(5, 5)][string[]]$Takes,
    [string]$OutputDirectory = '.godot/promo-landscape-weather',
    [string]$Ffmpeg = 'ffmpeg'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$encoder = (Get-Command $Ffmpeg -CommandType Application).Source
$shot = Get-Content -Raw -LiteralPath (Join-Path $root 'tests/playgrounds/promo/shots/W5.json') | ConvertFrom-Json
$locations = @($shot) + $shot.variants
$fps = 60
$sampleRate = 48000
$overlapSamples = 11520 # The incoming road and weather sound leads each picture cut by 0.24 s.
$movies = @()
$filters = @()
$videoLabels = ''
$totalFrames = 0

for ($index = 0; $index -lt $Takes.Count; $index++) {
    $directory = $Takes[$index]
    $take = Get-Content -Raw -LiteralPath (Join-Path $directory 'take.json') | ConvertFrom-Json
    $location = $locations[$index]
    if ($take.shot -ne 'W5' -or $take.variant -ne $index -or $take.fps -ne $fps -or
        $take.seed -ne $location.seed -or $take.distance -ne $location.distance) {
        throw "Expected W5 variant $index, seed $($location.seed), at $($location.distance) m and $fps fps in $directory."
    }

    $startCue = $location.timeline | Where-Object name -EQ 'landscape_start'
    $endCue = $location.timeline | Where-Object name -EQ 'landscape_end'
    $startMark = $take.markers | Where-Object name -EQ 'landscape_start'
    $endMark = $take.markers | Where-Object name -EQ 'landscape_end'
    $frameCount = [int][Math]::Round(($endCue.at - $startCue.at) * $fps)
    if ($null -eq $startMark.frame -or $null -eq $endMark.frame -or $startMark.frame -lt 0 -or
        [Math]::Abs(($endMark.frame - $startMark.frame) - $frameCount) -gt 1) {
        throw "The W5 drive in $directory is missing the expected cut markers."
    }

    $totalFrames += $frameCount
    $first = [int]$startMark.frame + 1
    $last = $first + $frameCount
    $firstSample = [int]($first * $sampleRate / $fps)
    if ($index -gt 0) { $firstSample -= $overlapSamples }
    $lastSample = [int]($last * $sampleRate / $fps)
    $movies += @('-i', (Resolve-Path -LiteralPath (Join-Path $directory 'take.avi')).Path)
    $filters += "[${index}:v]trim=start_frame=${first}:end_frame=${last},setpts=PTS-STARTPTS,scale=out_range=tv,format=yuv420p[v$index]"
    $filters += "[${index}:a]aresample=${sampleRate},atrim=start_sample=${firstSample}:end_sample=${lastSample},asetpts=PTS-STARTPTS[a$index]"
    $videoLabels += "[v$index]"
}

$filters += "${videoLabels}concat=n=$($Takes.Count):v=1:a=0[picture]"
$audioLabel = 'a0'
for ($index = 1; $index -lt $Takes.Count; $index++) {
    $filters += "[$audioLabel][a$index]acrossfade=ns=${overlapSamples}:c1=qsin:c2=qsin[mix$index]"
    $audioLabel = "mix$index"
}
$duration = $totalFrames / $fps
$endTimeline = $locations[-1].timeline
$blink = $endTimeline | Where-Object do -EQ 'eyes'
$endCue = $endTimeline | Where-Object name -EQ 'landscape_end'
$fadeAt = ($duration - ($endCue.at - $blink.at)).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
$filters += "[$audioLabel]highpass=f=55,volume=8dB,afade=t=in:d=0.22,afade=t=out:st=${fadeAt}:d=0.52[sound]"

$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$movie = Join-Path $output 'promo-landscape-weather-review.mp4'
& $encoder -nostdin -y -hide_banner -loglevel warning @movies `
    -filter_complex_threads 2 -filter_complex ($filters -join ';') -map '[picture]' -map '[sound]' `
    -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k -movflags +faststart $movie
if ($LASTEXITCODE -ne 0) { throw "FFmpeg exited with code $LASTEXITCODE." }
Get-Item -LiteralPath $movie
