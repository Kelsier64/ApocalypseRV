[CmdletBinding()]
param(
    [string]$Godot = 'godot',
    [ValidateSet('quick', 'integration', 'slow', 'assets', 'smoke', 'full')][string]$Suite = 'quick',
    [string[]]$TestFilter = @(),
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 240,
    [string]$StartAt = '',
    [switch]$List,
    [switch]$Smoke,
    [switch]$SkipImport,
    [switch]$RealTime,
    [switch]$FailFast
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$catalog = Get-Content (Join-Path $projectRoot 'tests/suites.json') -Raw | ConvertFrom-Json
if ($catalog.version -ne 1 -or $catalog.groups -isnot [PSCustomObject] -or $catalog.retired -isnot [PSCustomObject]) {
    throw 'Invalid tests/suites.json schema (expected version 1, groups and retired objects)'
}
$groupNames = @($catalog.groups.PSObject.Properties.Name)
if (@(Compare-Object @('quick', 'integration', 'slow', 'assets') $groupNames).Count -ne 0) {
    throw 'Catalog groups must be exactly quick, integration, slow and assets'
}
$available = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter 'test_*.gd' -File | Sort-Object Name)
$classified = @{}
foreach ($group in $catalog.groups.PSObject.Properties) {
    if ($group.Value -isnot [Array]) { throw "Catalog group must be an array: $($group.Name)" }
    foreach ($name in $group.Value) {
        if ($name -isnot [string] -or $name -notmatch '^test_[a-z0-9_]+$') { throw 'Invalid catalog test name' }
        if ($classified.ContainsKey($name)) { throw "Duplicate test classification: $name" }
        $classified[$name] = $group.Name
    }
}
foreach ($entry in $catalog.retired.PSObject.Properties) {
    if ($entry.Name -notmatch '^test_[a-z0-9_]+$' -or $entry.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Value)) {
        throw 'Retired tests require a valid name and a reason'
    }
    if ($classified.ContainsKey($entry.Name)) { throw "Duplicate retired test: $($entry.Name)" }
    $classified[$entry.Name] = 'retired'
}
# A new test must be classified; never silently omit it from the default/CI suites.
foreach ($test in $available) {
    if (-not $classified.ContainsKey($test.BaseName)) { throw "Unclassified test: $($test.BaseName). Add it to tests/suites.json" }
}
foreach ($name in $classified.Keys) {
    if ($name -notin $available.BaseName) { throw "Catalog references missing test: $name" }
}
$filtered = $PSBoundParameters.ContainsKey('TestFilter')
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
} else {
    $tests = @($available | Where-Object {
        $classified[$_.BaseName] -eq $Suite -or ($Suite -eq 'full' -and $classified[$_.BaseName] -ne 'retired')
    })
}
$includeSmoke = $Smoke -or (-not $filtered -and $Suite -in @('smoke', 'full'))
if ($tests.Count -eq 0 -and -not $includeSmoke) { throw "No tests selected for suite: $Suite" }
if ($StartAt) {
    if ($StartAt -notin $tests.BaseName) { throw "Unknown starting test: $StartAt" }
    $tests = @($tests | Where-Object { $_.BaseName -ge $StartAt })
}
$selection = @(foreach ($test in $tests) {
    [PSCustomObject]@{ Name = $test.BaseName; Suite = $classified[$test.BaseName] }
})
if ($includeSmoke) { $selection += [PSCustomObject]@{ Name = 'main-scene'; Suite = 'smoke' } }
if ($List) {
    $selection
    Write-Host "Selected $($selection.Count) checks. Engine not launched."
    return
}
$executable = (Get-Command $Godot -ErrorAction Stop).Source
$expectedVersion = (Get-Content (Join-Path $projectRoot '.godot-version') -Raw).Trim()
$actualVersion = (& $executable --version | Out-String).Trim()
if ($actualVersion -notlike "$expectedVersion.stable.*") { throw "Expected Godot $expectedVersion.stable, found $actualVersion" }
$runName = if ($filtered) { 'selected' } else { $Suite }
$logDirectory = Join-Path $projectRoot ('.godot/test-logs/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + "-$runName-$PID")
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$manifest = @(
    "Commit: $(& git -C $projectRoot rev-parse HEAD)",
    "Working tree: $((& git -C $projectRoot status --porcelain | Out-String).Trim())",
    "Engine: $actualVersion", "OS: $([Environment]::OSVersion)",
    "Suite: $runName", "Rendering: headless / dummy", "Real time: $RealTime",
    "Import: $(-not $SkipImport)", "Timeout per check: $TimeoutSeconds seconds"
) + @($selection | ForEach-Object { "$($_.Suite): $($_.Name)" })
$manifest | Set-Content (Join-Path $logDirectory 'manifest.txt')
Write-Host "Godot $actualVersion | $runName | $($selection.Count) checks"
Write-Host "Logs: $logDirectory"
$results = [Collections.Generic.List[object]]::new()
$total = [Diagnostics.Stopwatch]::StartNew()
$script:cleanupFailed = $false
function Save-Results {
    $report = [ordered]@{
        suite = $runName; engine = $actualVersion; real_time = [bool]$RealTime
        elapsed_seconds = [Math]::Round($total.Elapsed.TotalSeconds, 3)
        selected = @($selection); results = @($results.ToArray())
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $logDirectory 'results.json')
    $results.ToArray() | Export-Csv (Join-Path $logDirectory 'timings.csv') -NoTypeInformation
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
                    $script:cleanupFailed = $true
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
    if ($script:cleanupFailed) { throw $detail }
    return ($status -eq 'PASS')
}
try {
    if (-not $SkipImport) {
        if (-not (Invoke-GodotCheck 'import' @('--editor', '--import', '--quit'))) {
            throw "Import failed. See $logDirectory"
        }
    } elseif (-not (Test-Path (Join-Path $projectRoot '.godot/global_script_class_cache.cfg'))) {
        throw '-SkipImport requires a previously imported project. Run once without it.'
    }
    foreach ($test in $tests) {
        $testArguments = @('-s', ('res://tests/' + $test.Name))
        # Fixed render delta removes wall-clock throttling, preserving the project
        # physics tick, solver configuration, frame counts and simulated duration.
        if (-not $RealTime) { $testArguments += @('--fixed-fps', '60') }
        $passed = Invoke-GodotCheck $test.BaseName $testArguments $true
        if (-not $passed -and $FailFast) { break }
    }
    if ($includeSmoke -and (-not $FailFast -or @($results | Where-Object { $_.status -ne 'PASS' }).Count -eq 0)) {
        $smokeArguments = @('-s', 'res://tests/main_scene_smoke.gd')
        if (-not $RealTime) { $smokeArguments += @('--fixed-fps', '60') }
        $null = Invoke-GodotCheck 'main-scene' $smokeArguments $true '(?m)^PASS: WORLD_READY_FOR_PLAY\b'
    }
} finally {
    Save-Results
    Write-Host ("Finished in {0:N2}s. Slowest checks:" -f $total.Elapsed.TotalSeconds)
    $results | Sort-Object seconds -Descending | Select-Object -First 5 name, status, seconds | Format-Table -AutoSize | Out-Host
}
$failed = @($results | Where-Object { $_.status -ne 'PASS' })
if ($failed.Count -gt 0) { throw "$($failed.Count) checks failed. See $logDirectory/results.json" }
