<#
.SYNOPSIS
Edits the two T1 captures into the first three trailer scenes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Cab,
    [Parameter(Mandatory)][string]$Exterior,
    [string]$Narration = '.godot/promo/narration',
    [string]$OutputDirectory = '.godot/promo-opening',
    [string]$Ffmpeg = 'ffmpeg'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$encoder = (Get-Command $Ffmpeg -CommandType Application).Source
$cabMovie = (Resolve-Path -LiteralPath (Join-Path $Cab 'take.avi')).Path
$exteriorMovie = (Resolve-Path -LiteralPath (Join-Path $Exterior 'take.avi')).Path
$assignment = (Resolve-Path -LiteralPath (Join-Path $Narration '02.wav')).Path
$briefing = (Resolve-Path -LiteralPath (Join-Path $Narration '03.wav')).Path
$bed = Join-Path $root 'assets/audio/promo/memory_intro.wav'

$fps = 60
$opening = Get-Content -Raw -LiteralPath (Join-Path $root 'tests/playgrounds/promo/shots/T1.json') | ConvertFrom-Json
$cues = $opening.timeline
$exteriorAt = ($cues | Where-Object name -eq 'exterior_cut').at
$briefingAt = ($cues | Where-Object name -eq 'briefing_cut').at
$lineAt = ($cues | Where-Object { $_.do -eq 'line' -and $_.id -eq 1 }).at
$cutCues = @{
    'exterior_cut' = $exteriorAt
    'briefing_cut' = $briefingAt
    'blink_closed' = ($cues | Where-Object name -eq 'blink_closed').at
    'line 1' = $lineAt
}

function Get-TakeStart([string]$Directory) {
    $take = Get-Content -Raw -LiteralPath (Join-Path $Directory 'take.json') | ConvertFrom-Json
    if ($take.shot -ne 'T1' -or $take.variant -ne 0 -or $take.fps -ne $fps) {
        throw "Expected a T1 opening at $fps fps in $Directory."
    }
    foreach ($name in $cutCues.Keys) {
        $marker = @($take.markers | Where-Object name -eq $name)
        if ($marker.Count -ne 1 -or [Math]::Abs($marker[0].frame - $take.start_frame - $cutCues[$name] * $fps) -gt 2) {
            throw "The T1 take in $Directory does not match the current timing for $name."
        }
    }
    return [int]$take.start_frame
}

# Use the same take clock for the cab and exterior so the RV keeps its place in the drive.
$cabStart = Get-TakeStart $Cab
$exteriorStart = Get-TakeStart $Exterior
$exteriorCut = $exteriorAt * $fps
$briefingCut = $briefingAt * $fps
$end = ($cues | Where-Object do -eq 'end').at * $fps
$samplesPerFrame = 48000 / $fps
$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$subtitleFile = Join-Path $output 'opening.ass'
function Get-Subtitle([double]$Start, [double]$End, [string]$Text) {
    $format = 'h\:mm\:ss\.ff'
    $from = [TimeSpan]::FromMilliseconds([Math]::Round($Start * 1000)).ToString($format)
    $to = [TimeSpan]::FromMilliseconds([Math]::Round($End * 1000)).ToString($format)
    "Dialogue: 0,$from,$to,Dispatch,,0,0,0,,$Text"
}

$subtitleHeader = @'
[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Dispatch,Arial,34,&H00F8F8F8,&H00F8F8F8,&H000B0B0B,&H64000000,0,0,0,0,100,100,0,0,1,2,0,2,56,56,38,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
'@
@(
    $subtitleHeader
    (Get-Subtitle $lineAt ($lineAt + 3.62) 'This is Shelter Four dispatch.')
    (Get-Subtitle $exteriorAt ($exteriorAt + 3.33) 'Unit 4712.')
    (Get-Subtitle ($exteriorAt + 3.56) ($exteriorAt + 7.52) 'You are assigned to Route 9.')
    (Get-Subtitle ($exteriorAt + 7.80) ($exteriorAt + 10.86) 'Proceed to relay station.')
    (Get-Subtitle $briefingAt ($briefingAt + 1.64) 'Mission briefing.')
) | Set-Content -LiteralPath $subtitleFile -Encoding ascii

function Get-CutFilters([int]$InputIndex, [int]$FirstFrame, [int]$LastFrame, [string]$Name) {
    $firstSample = $FirstFrame * $samplesPerFrame
    $lastSample = $LastFrame * $samplesPerFrame
    $grade = if ($InputIndex -eq 0) { ",curves=all='0/0 0.06/0.105 0.17/0.235 0.5/0.54 1/1'" } else { '' }
    "[${InputIndex}:v]trim=start_frame=${FirstFrame}:end_frame=${LastFrame},setpts=PTS-STARTPTS$grade,scale=out_range=tv,format=yuv420p[v$Name]"
    "[${InputIndex}:a]atrim=start_sample=${firstSample}:end_sample=${lastSample},asetpts=PTS-STARTPTS[a$Name]"
}

$culture = [Globalization.CultureInfo]::InvariantCulture
$cabFade = ($exteriorAt - 0.04).ToString('0.00', $culture)
$exteriorFade = ($briefingAt - $exteriorAt - 0.04).ToString('0.00', $culture)
$filters = @(
    (Get-CutFilters 0 $cabStart ($cabStart + $exteriorCut) 'cab')
    (Get-CutFilters 1 ($exteriorStart + $exteriorCut) ($exteriorStart + $briefingCut) 'exterior')
    (Get-CutFilters 0 ($cabStart + $briefingCut) ($cabStart + $end) 'briefing')
    "[acab]afade=t=in:st=1:d=0.32,afade=t=out:st=${cabFade}:d=0.04[cab]"
    "[aexterior]volume=0.55,afade=t=in:d=0.04,afade=t=out:st=${exteriorFade}:d=0.04[road]"
    '[2:a]highpass=f=320,lowpass=f=3150,aecho=1:0.82:30|63:0.12|0.04,volume=1.6,aresample=48000,aformat=channel_layouts=stereo[assignment]'
    '[road][assignment]amix=inputs=2:duration=first:normalize=0[exterior]'
    '[abriefing]afade=t=in:d=0.04,asplit[dry][muffled]'
    "[dry]volume='if(isnan(t),1,max(0,1-t/0.55))':eval=frame[near]"
    "[muffled]lowpass=f=430,volume='if(isnan(t),0,min(1,t/0.55))':eval=frame[far]"
    '[3:a]volume=1.4,aresample=48000,aformat=channel_layouts=stereo[briefing_voice]'
    '[4:a]volume=0.30,aformat=channel_layouts=stereo[memory]'
    '[near][far][briefing_voice][memory]amix=inputs=4:duration=first:normalize=0[briefing]'
    '[vcab][cab][vexterior][exterior][vbriefing][briefing]concat=n=3:v=1:a=1[picture][sound]'
    '[picture]ass=opening.ass[captioned]'
) -join ';'

Push-Location -LiteralPath $output
try {
    & $encoder -nostdin -y -hide_banner -loglevel warning -i $cabMovie -i $exteriorMovie -i $assignment -i $briefing -i $bed `
        -filter_complex_threads 2 -filter_complex $filters -map '[captioned]' -map '[sound]' `
        -c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k -movflags +faststart 'promo-scenes-01-03-review.mp4'
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg exited with code $LASTEXITCODE." }
} finally {
    Pop-Location
}
Get-Item -LiteralPath (Join-Path $output 'promo-scenes-01-03-review.mp4')
