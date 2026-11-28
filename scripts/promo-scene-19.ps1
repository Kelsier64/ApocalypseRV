<#
.SYNOPSIS
Edits four W2 landscapes into the trailer's wordless world montage.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateCount(4, 4)][string[]]$Takes,
    [string]$OutputDirectory = '.godot/promo-scene-19',
    [string]$Ffmpeg = 'ffmpeg'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'promo-eyelids.ps1')
$root = Split-Path $PSScriptRoot -Parent
$encoder = (Get-Command $Ffmpeg -CommandType Application).Source
$fps = 60
$sampleRate = 48000
$cuts = @(0, 160, 320, 480, 840)
$duration = $cuts[-1] / $fps
$shot = Get-Content -Raw -LiteralPath (Join-Path $root 'tests/playgrounds/promo/shots/W2.json') | ConvertFrom-Json
$movies = @()
$filters = @()

# Keep the same elapsed rail time on either side of each cut.
for ($index = 0; $index -lt $Takes.Count; $index++) {
    $directory = $Takes[$index]
    $take = Get-Content -Raw -LiteralPath (Join-Path $directory 'take.json') | ConvertFrom-Json
    $location = if ($index -eq 0) { $shot } else { $shot.variants[$index - 1] }
    if ($take.shot -ne 'W2' -or $take.variant -ne $index -or $take.fps -ne $fps -or
        $take.seed -ne $location.seed -or $take.distance -ne $location.distance -or
        $null -eq $take.start_frame -or $take.start_frame -lt 0) {
        throw "Expected W2 variant $index, seed $($location.seed), at $($location.distance) m and $fps fps in $directory."
    }
    $movies += @('-i', (Resolve-Path -LiteralPath (Join-Path $directory 'take.avi')).Path)
    $first = [int]$take.start_frame + $cuts[$index] + 1
    $last = [int]$take.start_frame + $cuts[$index + 1] + 1
    $filters += "[${index}:v]trim=start_frame=${first}:end_frame=${last},setpts=PTS-STARTPTS,scale=out_range=tv,format=yuv420p[v$index]"
}

$blink = Get-PromoEyelidsFilter '13.2' '0.34'
$firstBeat = [int]($cuts[1] * $sampleRate / $fps)
$secondBeat = [int]($cuts[2] * $sampleRate / $fps)
$thirdBeat = [int]($cuts[3] * $sampleRate / $fps)
$filters += @(
    "[v0][v1][v2][v3]concat=n=4:v=1:a=0,$blink[picture]"
    '[4:a]atempo=0.72,aformat=sample_rates=48000:channel_layouts=stereo,afade=t=in:d=0.18,afade=t=out:st=6.5:d=2.25,volume=-6dB[memory]'
    '[5:a]atrim=start=4:end=18,asetpts=PTS-STARTPTS,aformat=sample_rates=48000:channel_layouts=stereo,highpass=f=65,lowpass=f=850,afade=t=in:d=0.24,afade=t=out:st=13.1:d=0.5,volume=-9dB[wind]'
    "aevalsrc='0.16*(sin(2*PI*57*t)+0.24*sin(2*PI*114*t))*min(t*100,1)*exp(-14*t)':s=${sampleRate}:d=0.55,aformat=channel_layouts=stereo,asplit=3[pulse1][pulse2][pulse3]"
    "[pulse1]adelay=${firstBeat}S:all=1[beat1]"
    "[pulse2]adelay=${secondBeat}S:all=1[beat2]"
    "[pulse3]adelay=${thirdBeat}S:all=1[beat3]"
    '[wind][memory][beat1][beat2][beat3]amix=inputs=5:duration=first:normalize=0[sound]'
)

$music = Join-Path $root 'assets/audio/promo/memory_intro.wav'
$wind = Join-Path $root 'assets/audio/weather/wind_breeze.ogg'
$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$movie = Join-Path $output 'promo-scene-19-review.mp4'
& $encoder -nostdin -y -hide_banner -loglevel warning @movies -i $music -i $wind `
    -filter_complex_threads 2 -filter_complex ($filters -join ';') -map '[picture]' -map '[sound]' `
    -t $duration -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k -movflags +faststart $movie
if ($LASTEXITCODE -ne 0) { throw "FFmpeg exited with code $LASTEXITCODE." }
Get-Item -LiteralPath $movie
