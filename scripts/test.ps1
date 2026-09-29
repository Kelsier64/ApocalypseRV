param([string]$Godot = 'godot', [string[]]$TestFilter = @('test_*.gd'), [ValidateRange(1, 600)][int]$TimeoutSeconds = 240, [string]$StartAt = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$logDirectory = Join-Path $projectRoot '.godot/test-logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$executable = (Get-Command $Godot -ErrorAction Stop).Source
$expectedVersion = (Get-Content (Join-Path $projectRoot '.godot-version') -Raw).Trim()
$actualVersion = (& $executable --version | Out-String).Trim()
if ($actualVersion -notlike "$expectedVersion.stable.*") { throw "Expected Godot $expectedVersion.stable, found $actualVersion" }
$patterns = @(foreach ($filterArgument in $TestFilter) { $filterArgument -split ',' })
if ($patterns.Count -eq 0) { throw 'At least one test filter is required' }
$discoveredTests = foreach ($pattern in $patterns) {
    $pattern = $pattern.Trim()
    if ([string]::IsNullOrWhiteSpace($pattern)) { throw 'Test filters cannot be empty' }
    $matchingTests = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter $pattern -File)
    if ($matchingTests.Count -eq 0) { throw "No tests discovered for filter: $pattern" }
    $matchingTests
}
$tests = @($discoveredTests | Sort-Object Name -Unique)
if ($tests.Count -eq 0) { throw "No tests discovered for $($patterns -join ', ')" }
if ($StartAt) {
    if ($StartAt -notin $tests.BaseName) { throw "Unknown starting test: $StartAt" }
    $tests = @($tests | Where-Object { $_.BaseName -ge $StartAt })
}
$manifest = @("Commit: $(& git -C $projectRoot rev-parse HEAD)", "Working tree: $((& git -C $projectRoot status --porcelain | Out-String).Trim())", "Engine: $actualVersion", "OS: $([Environment]::OSVersion)", 'Rendering: headless / dummy', "Tests: $($tests.Count)") + $tests.Name
$manifest | Set-Content (Join-Path $logDirectory 'manifest.txt')
Write-Host ($manifest -join "`n")
function Invoke-GodotCheck([string]$Name, [string[]]$ExtraArguments, [bool]$RequirePass = $false, [string]$PassPattern = '(?m)^PASS:') {
    $log = Join-Path $logDirectory ($Name + '.log')
    [IO.File]::WriteAllText($log, '')
    $arguments = @('--headless', '--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $log + '"')) + $ExtraArguments
    $process = Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill()
        throw "$Name timed out after $TimeoutSeconds seconds. See $log"
    }
    $process.Refresh()
    $output = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
    # The restricted Windows environment cannot read the OS certificate store.
    # Ignore only that specific engine diagnostic, never script/runtime errors.
    $errors = $output -split "`n" | Where-Object { $_ -match '(SCRIPT ERROR:|ERROR:|FAIL:|Program crashed)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.' }
    if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output) -or $errors -or ($RequirePass -and $output -notmatch $PassPattern)) {
        Write-Host $output
        throw "$Name failed (exit $($process.ExitCode)). See $log"
    }
    Write-Host "PASS: $Name"
}

Invoke-GodotCheck 'import' @('--editor', '--import', '--quit')
foreach ($test in $tests) {
    $testArguments = @('-s', ('res://tests/' + $test.Name))
    # Long outdoor round trips exceed two minutes of simulated play. Keep
    # configured physics timing while letting headless rendering run unthrottled.
    # Navigation publication also needs consistent physics/process scheduling.
    if ($test.BaseName -like 'test_outdoor_*' -or $test.BaseName -in @('test_rv_handling', 'test_tire_handling', 'test_checkpoint_failures', 'test_bunker_content', 'test_bunker_encounter', 'test_bunker_extraction', 'test_poi_transition_persistence', 'test_interior_traversal', 'test_interior_doorways', 'test_interior_navigation', 'test_raker_cabin', 'test_raker_neck', 'test_raker_grab_vehicle')) { $testArguments += @('--fixed-fps', '60') }
    # Sample every 60 Hz physics step; these tests never override the project tick.
    if ($test.BaseName -in @('test_player_ragdoll_v020', 'test_player_death', 'test_player_animation', 'test_player_jump_animation', 'test_player_climb_animation')) { $testArguments += @('--fixed-fps', '60') }
    Invoke-GodotCheck $test.BaseName $testArguments $true
}
Invoke-GodotCheck 'main-scene' @('-s', 'res://tests/main_scene_smoke.gd') $true '(?m)^PASS: WORLD_READY_FOR_PLAY\b'
