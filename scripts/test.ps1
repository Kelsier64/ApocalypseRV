[CmdletBinding()]
param(
    [string]$Godot = 'godot',
    [string[]]$TestFilter = @(),
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 240,
    [switch]$List,
    [switch]$Smoke,
    [switch]$SmokeOnly,
    [switch]$SkipImport,
    [switch]$RealTime
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$available = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter 'test_*.gd' -File | Sort-Object Name)
$filtered = $PSBoundParameters.ContainsKey('TestFilter')
if ($SmokeOnly -and $filtered) { throw '-SmokeOnly cannot be combined with -TestFilter' }
if ($filtered) {
    $patterns = @(foreach ($argument in $TestFilter) { $argument -split ',' })
    if ($patterns.Count -eq 0) { throw 'At least one test filter is required' }
    $selected = @(foreach ($pattern in $patterns) {
        $pattern = $pattern.Trim()
        if ([string]::IsNullOrWhiteSpace($pattern)) { throw 'Test filters cannot be empty' }
        $matches = @($available | Where-Object { $_.Name -like $pattern })
        if ($matches.Count -eq 0) { throw "No tests discovered for filter: $pattern" }
        $matches
    })
    $tests = @($selected | Sort-Object Name -Unique)
} elseif ($SmokeOnly) { $tests = @() }
else { $tests = $available }
$includeSmoke = $Smoke -or -not $filtered
$selection = @(foreach ($test in $tests) {
    [PSCustomObject]@{ Name = $test.BaseName }
})
if ($includeSmoke) { $selection += [PSCustomObject]@{ Name = 'main-scene' } }
if ($List) {
    $selection
    Write-Host "Selected $($selection.Count) checks. Engine not launched."
    return
}
$executable = (Get-Command $Godot -ErrorAction Stop).Source
$expectedVersion = (Get-Content (Join-Path $projectRoot '.godot-version') -Raw).Trim()
$actualVersion = (& $executable --version | Out-String).Trim()
if ($actualVersion -notlike "$expectedVersion.stable.*") { throw "Expected Godot $expectedVersion.stable, found $actualVersion" }
$runName = if ($SmokeOnly) { 'smoke' } elseif ($filtered) { 'selected' } else { 'all' }
$logDirectory = Join-Path $projectRoot ('.godot/test-logs/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + "-$runName-$PID")
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$metadata = [ordered]@{
    mode = $runName; commit = (& git -C $projectRoot rev-parse HEAD | Out-String).Trim()
    working_tree = (& git -C $projectRoot status --porcelain | Out-String).Trim()
    engine = $actualVersion; os = [Environment]::OSVersion.ToString()
    real_time = [bool]$RealTime; import = -not $SkipImport; timeout_seconds = $TimeoutSeconds
}
Write-Host "Godot $actualVersion | $runName | $($selection.Count) checks"
Write-Host "Logs: $logDirectory"
$results = [Collections.Generic.List[object]]::new()
$total = [Diagnostics.Stopwatch]::StartNew()
function Save-Results {
    $report = [ordered]@{
        metadata = $metadata
        elapsed_seconds = [Math]::Round($total.Elapsed.TotalSeconds, 3)
        selected = @($selection); results = @($results.ToArray())
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $logDirectory 'results.json')
}
function Invoke-GodotCheck([string]$Name, [string[]]$ExtraArguments, [bool]$RequirePass = $false, [string]$PassPattern = '(?m)^PASS:') {
    $log = Join-Path $logDirectory ($Name + '.log')
    [IO.File]::WriteAllText($log, '')
    $arguments = @('--headless', '--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $log + '"')) + $ExtraArguments
    $elapsed = [Diagnostics.Stopwatch]::StartNew()
    $status = 'FAIL'
    $detail = ''
    $exitCode = $null
    $process = $null
    try {
        $process = Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $status = 'TIMEOUT'
            $detail = "Exceeded $TimeoutSeconds seconds"
            # Godot's console launcher (and batch test doubles) can own a child
            # process. Terminate only this launched tree so it cannot keep writing
            # saves or consuming CPU while the next test runs. Works in PS 5.1.
            if (-not $process.HasExited) {
                try {
                    if ($PSVersionTable.PSEdition -eq 'Core') {
                        $process.Kill($true)
                    } else {
                        & "$env:SystemRoot/System32/taskkill.exe" /PID $process.Id /T /F 2>&1 | Out-Null
                        if ($LASTEXITCODE -ne 0 -and -not $process.HasExited) { throw 'Process-tree termination failed' }
                    }
                } catch {
                    if (-not $process.HasExited) { $process.Kill() }
                    throw "Unable to terminate test descendants: $($_.Exception.Message). Remaining checks stopped."
                }
            }
            $process.WaitForExit()
        } else {
            $process.Refresh()
            $exitCode = $process.ExitCode
            $output = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
            # Ignore only the restricted Windows certificate-store diagnostic.
            $errors = @($output -split "`n" | Where-Object {
                $_ -match '(SCRIPT ERROR:|ERROR:|FAIL:|Program crashed)' -and
                $_ -notmatch '^ERROR: Failed to read the root certificate store\.'
            })
            if ($exitCode -ne 0) { $detail = "Exit code $exitCode" }
            elseif ([string]::IsNullOrWhiteSpace($output)) { $detail = 'Empty engine log' }
            elseif ($errors.Count -gt 0) { $detail = $errors -join "`n" }
            elseif ($RequirePass -and $output -notmatch $PassPattern) { $detail = 'Missing PASS marker' }
            else { $status = 'PASS' }
        }
    } catch { $detail = $_.Exception.Message }
    finally {
        if ($null -ne $process) { $process.Dispose() }
        $results.Add([PSCustomObject]@{
            name = $Name; status = $status; seconds = [Math]::Round($elapsed.Elapsed.TotalSeconds, 3)
            exit_code = $exitCode; detail = $detail; log = $log
        })
        Save-Results
    }
    Write-Host ("{0}: {1} ({2:N2}s)" -f $status, $Name, $elapsed.Elapsed.TotalSeconds)
    if ($status -ne 'PASS') {
        Write-Host $detail
        Get-Content -LiteralPath $log -Tail 30 | Write-Host
    }
    if ($status -ne 'PASS') { throw "$Name failed. See $log" }
}
try {
    if (-not $SkipImport) {
        Invoke-GodotCheck 'import' @('--editor', '--import', '--quit')
    } elseif (-not (Test-Path (Join-Path $projectRoot '.godot/global_script_class_cache.cfg'))) {
        throw '-SkipImport requires a previously imported project. Run once without it.'
    }
    foreach ($test in $tests) {
        $testArguments = @('-s', ('res://tests/' + $test.Name))
        # Fixed render delta removes wall-clock throttling, preserving the project
        # physics tick, solver configuration, frame counts and simulated duration.
        if (-not $RealTime) { $testArguments += @('--fixed-fps', '60') }
        Invoke-GodotCheck $test.BaseName $testArguments $true
    }
    if ($includeSmoke) {
        $smokeArguments = @('-s', 'res://tests/main_scene_smoke.gd')
        if (-not $RealTime) { $smokeArguments += @('--fixed-fps', '60') }
        Invoke-GodotCheck 'main-scene' $smokeArguments $true '(?m)^PASS: WORLD_READY_FOR_PLAY\b'
    }
} finally {
    Save-Results
    Write-Host ("Finished in {0:N2}s. Slowest checks:" -f $total.Elapsed.TotalSeconds)
    $results | Sort-Object seconds -Descending | Select-Object -First 5 name, status, seconds | Format-Table -AutoSize | Out-Host
}
