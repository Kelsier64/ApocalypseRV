param([string]$Gltfpack = 'gltfpack')
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$sourcePath = Join-Path $repositoryRoot 'art_source/retired_props/2026-09-29/oil_barrel.glb'
$sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceHash -ne '58326447acdfb7d8ba9fc90c8efc345fd9b8e365d93393f287aba8b192646694') {
    throw 'Original barrel hash differs from the verified comparison source.'
}
$variants = @(
    @{ Name = 'strict'; Error = '0.01'; Flags = @() },
    @{ Name = 'permissive'; Error = '0.01'; Flags = @('-sp') },
    @{ Name = 'permissive-update'; Error = '0.01'; Flags = @('-sp', '-sv') },
    @{ Name = 'permissive-5pct'; Error = '0.05'; Flags = @('-sp', '-sv') },
    @{ Name = 'aggressive'; Error = '0.05'; Flags = @('-sa') },
    @{ Name = 'permissive-maxerror'; Error = '1'; Flags = @('-sp', '-sv') }
)
$timings = foreach ($variant in $variants) {
    $outputPath = Join-Path $PSScriptRoot "$($variant.Name).glb"
    $reportPath = Join-Path $PSScriptRoot "$($variant.Name)-report.json"
    $arguments = @('-i', $sourcePath, '-o', $outputPath, '-si', '0.006001848',
        '-se', $variant.Error) + $variant.Flags + @('-noq', '-kn', '-km', '-r', $reportPath, '-v')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    & $Gltfpack @arguments 2>&1 | Tee-Object -FilePath (Join-Path $PSScriptRoot "$($variant.Name)-tool.log") | Out-Host
    $timer.Stop()
    if ($LASTEXITCODE -ne 0) { throw "$($variant.Name) exited with $LASTEXITCODE" }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    [pscustomobject]@{
        name = $variant.Name
        elapsed_seconds = $timer.Elapsed.TotalSeconds
        triangles = $report.render.triangleCount
        bytes = (Get-Item -LiteralPath $outputPath).Length
        arguments = $arguments
    }
}
$timings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'timings.json') -Encoding utf8
$timings | Select-Object name, elapsed_seconds, triangles, bytes | Format-Table
