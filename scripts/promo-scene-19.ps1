<#
.SYNOPSIS
Edits the three W2 captures into the trailer's wordless seed comparison.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateCount(3, 3)][string[]]$Takes,
    [string]$OutputDirectory = '.godot/promo-scene-19',
    [string]$Ffmpeg = 'ffmpeg'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$encoder = (Get-Command $Ffmpeg -CommandType Application).Source
$fps = 60
$sampleRate = 48000
$cuts = @(0, 100, 200, 840)
$duration = $cuts[-1] / $fps
$movies = @()
$filters = @()

# Keep the same elapsed rail time on either side of each cut.
for ($index = 0; $index -lt $Takes.Count; $index++) {
    $directory = $Takes[$index]
    $take = Get-Content -Raw -LiteralPath (Join-Path $directory 'take.json') | ConvertFrom-Json
    if ($take.shot -ne 'W2' -or $take.variant -ne $index -or $take.fps -ne $fps -or $null -eq $take.start_frame -or $take.start_frame -lt 0) {
        throw "Expected W2 variant $index at $fps fps in $directory."
    }
    $movies += @('-i', (Resolve-Path -LiteralPath (Join-Path $directory 'take.avi')).Path)
    $first = [int]$take.start_frame + $cuts[$index] + 1
    $last = [int]$take.start_frame + $cuts[$index + 1] + 1
    $filters += "[${index}:v]trim=start_frame=${first}:end_frame=${last},setpts=PTS-STARTPTS,scale=out_range=tv,format=yuv420p[v$index]"
}

# Reuse the shape and feather of player/san_eyelids.gdshader for the post-production blink.
$eyeClosure = 'clip((T-13.2)/0.34,0,1)'
$eyeOpening = '1.08-(1.12+0.15*pow(2*(X+0.5)/W-1,2))*ld(1)'
$lid = "st(0,$eyeClosure);st(1,ld(0)*ld(0)*(3-2*ld(0)));st(2,$eyeOpening);st(3,clip((abs(2*(Y+0.5)/H-1)-ld(2)+0.035)/0.07,0,1));"
$visible = '(1-ld(3)*ld(3)*(3-2*ld(3)))'
$blink = "geq=lum='${lid}16+(lum(X,Y)-16)*${visible}':cb='${lid}128+(cb(X,Y)-128)*${visible}':cr='${lid}128+(cr(X,Y)-128)*${visible}':enable='gte(t,13.2)'"
$firstBeat = [int]($cuts[1] * $sampleRate / $fps)
$secondBeat = [int]($cuts[2] * $sampleRate / $fps)
$filters += @(
    "[v0][v1][v2]concat=n=3:v=1:a=0,$blink[picture]"
    '[3:a]atempo=0.85,aformat=sample_rates=48000:channel_layouts=stereo,afade=t=in:d=0.18,afade=t=out:st=4.8:d=2.5,volume=-6dB[memory]'
    '[4:a]atrim=start=4:end=18,asetpts=PTS-STARTPTS,aformat=sample_rates=48000:channel_layouts=stereo,highpass=f=65,lowpass=f=850,afade=t=in:d=0.24,afade=t=out:st=13.1:d=0.5,volume=-9dB[wind]'
    "aevalsrc='0.16*(sin(2*PI*57*t)+0.24*sin(2*PI*114*t))*min(t*100,1)*exp(-14*t)':s=${sampleRate}:d=0.55,aformat=channel_layouts=stereo,asplit[pulse1][pulse2]"
    "[pulse1]adelay=${firstBeat}S:all=1[beat1]"
    "[pulse2]adelay=${secondBeat}S:all=1[beat2]"
    '[wind][memory][beat1][beat2]amix=inputs=4:duration=first:normalize=0[sound]'
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
