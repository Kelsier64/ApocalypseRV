# Isolated runner regression tests. No Godot installation or project import needed.
# Run with Windows PowerShell 5.1 or pwsh: -File scripts/test-runner.tests.ps1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$scratchRoot = Join-Path $repositoryRoot ('.godot/runner-self-tests/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null
$script:assertions = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Self-test failed: $Message" }
    $script:assertions++
}

function Write-Catalog([string]$Root, $Groups, $Retired = @{}) {
    foreach ($group in @('quick', 'integration', 'slow', 'assets')) {
        if (-not $Groups.Contains($group)) { $Groups[$group] = @() }
    }
    [ordered]@{ version = 1; groups = $Groups; retired = $Retired } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Root 'tests/suites.json') -Encoding UTF8
}

function New-Fixture([string]$Name) {
    $root = Join-Path $scratchRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts'), (Join-Path $root 'tests'), (Join-Path $root '.godot') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test.ps1') -Destination (Join-Path $root 'scripts/test.ps1')
    '4.7.2' | Set-Content -LiteralPath (Join-Path $root '.godot-version')
    $groups = [ordered]@{
        quick = @('test_alpha', 'test_bravo'); integration = @('test_charlie')
        slow = @('test_delta'); assets = @('test_echo')
    }
    foreach ($name in @('test_alpha', 'test_bravo', 'test_charlie', 'test_delta', 'test_echo', 'test_old')) {
        '# Dummy test: selection only' | Set-Content -LiteralPath (Join-Path $root "tests/$name.gd")
    }
    Write-Catalog $root $groups @{ test_old = 'Retained for direct invocation.' }
    return $root
}

function Invoke-Runner([string]$Root, [hashtable]$Parameters) {
    $rows = @()
    $failure = $null
    try { $rows = @(& (Join-Path $Root 'scripts/test.ps1') @Parameters 6>$null) }
    catch { $failure = $_.Exception.Message }
    return [PSCustomObject]@{ Rows = $rows; Failure = $failure }
}

function Assert-Selection([string]$Root, [hashtable]$Parameters, [string[]]$Expected) {
    $Parameters['List'] = $true
    # An invalid executable makes accidental engine launches fail this test.
    $Parameters['Godot'] = 'runner-self-test-engine-must-not-be-launched'
    $result = Invoke-Runner $Root $Parameters
    Assert-True ($null -eq $result.Failure) "Selection unexpectedly failed: $($result.Failure)"
    $actual = @($result.Rows | ForEach-Object { $_.Name })
    Assert-True (($actual -join ',') -ceq ($Expected -join ',')) "Selection expected [$($Expected -join ',')], got [$($actual -join ',')]"
}

function Assert-Rejected([string]$Root, [hashtable]$Parameters, [string]$Pattern) {
    $Parameters['List'] = $true
    $result = Invoke-Runner $Root $Parameters
    Assert-True ($null -ne $result.Failure -and $result.Failure -match $Pattern) "Expected rejection /$Pattern/, got '$($result.Failure)'"
}

$selectionRoot = New-Fixture 'selection project with spaces'
Assert-Selection $selectionRoot @{} @('test_alpha', 'test_bravo')
Assert-Selection $selectionRoot @{ Suite = 'integration' } @('test_charlie')
Assert-Selection $selectionRoot @{ Suite = 'slow' } @('test_delta')
Assert-Selection $selectionRoot @{ Suite = 'assets' } @('test_echo')
Assert-Selection $selectionRoot @{ Suite = 'smoke' } @('main-scene')
Assert-Selection $selectionRoot @{ Suite = 'full' } @('test_alpha', 'test_bravo', 'test_charlie', 'test_delta', 'test_echo', 'main-scene')
Assert-Selection $selectionRoot @{ Smoke = $true } @('test_alpha', 'test_bravo', 'main-scene')
Assert-Selection $selectionRoot @{ TestFilter = @('test_alpha.gd,test_bravo.gd', 'test_a*.gd') } @('test_alpha', 'test_bravo')
Assert-Selection $selectionRoot @{ Suite = 'full'; TestFilter = @('test_old.gd') } @('test_old')
Assert-Selection $selectionRoot @{ TestFilter = @('test_old.gd'); Smoke = $true } @('test_old', 'main-scene')
Assert-Selection $selectionRoot @{ StartAt = 'test_bravo' } @('test_bravo')
Assert-Selection $selectionRoot @{ TestFilter = @('test_echo.gd', 'test_alpha.gd', 'test_delta.gd'); StartAt = 'test_delta' } @('test_delta', 'test_echo')
Assert-Rejected $selectionRoot @{ TestFilter = @('test_alpha.gd', 'test_missing*.gd') } 'No tests discovered for filter'
Assert-Rejected $selectionRoot @{ TestFilter = @('test_alpha.gd,') } 'Test filters cannot be empty'
Assert-Rejected $selectionRoot @{ TestFilter = @() } 'At least one test filter is required'
Assert-Rejected $selectionRoot @{ StartAt = 'test_charlie' } 'Unknown starting test'
Assert-Rejected $selectionRoot @{ Suite = 'smoke'; StartAt = 'test_alpha' } 'Unknown starting test'

$duplicateRoot = New-Fixture 'duplicate'
Write-Catalog $duplicateRoot @{ quick = @('test_alpha', 'test_alpha') } @{}
Assert-Rejected $duplicateRoot @{} 'Duplicate test classification: test_alpha'
Write-Catalog $duplicateRoot @{ quick = @('test_alpha'); integration = @('test_alpha') } @{}
Assert-Rejected $duplicateRoot @{} 'Duplicate test classification: test_alpha'
Write-Catalog $duplicateRoot @{ quick = @('test_alpha') } @{ test_alpha = 'Invalid overlap.' }
Assert-Rejected $duplicateRoot @{} 'Duplicate retired test: test_alpha'

$unclassifiedRoot = New-Fixture 'unclassified'
'# New unclassified test' | Set-Content -LiteralPath (Join-Path $unclassifiedRoot 'tests/test_new.gd')
Assert-Rejected $unclassifiedRoot @{ TestFilter = @('test_alpha.gd') } 'Unclassified test: test_new'
$missingRoot = New-Fixture 'missing'
Write-Catalog $missingRoot @{ quick = @('test_alpha', 'test_bravo'); integration = @('test_charlie'); slow = @('test_delta'); assets = @('test_echo', 'test_missing') } @{ test_old = 'Retired.' }
Assert-Rejected $missingRoot @{} 'Catalog references missing test: test_missing'
Write-Catalog $missingRoot @{ quick = @('test_alpha', 'test_bravo'); integration = @('test_charlie'); slow = @('test_delta'); assets = @('test_echo') } @{ test_old = 'Retired.'; test_missing = 'Missing retired file.' }
Assert-Rejected $missingRoot @{} 'Catalog references missing test: test_missing'
$emptyRoot = New-Fixture 'empty suite'
Write-Catalog $emptyRoot @{ quick = @(); integration = @('test_alpha', 'test_bravo', 'test_charlie'); slow = @('test_delta'); assets = @('test_echo') } @{ test_old = 'Retired.' }
Assert-Rejected $emptyRoot @{} 'No tests selected for suite: quick'

$schemaRoot = New-Fixture 'invalid schemas'
$schemaCases = @(
    @{ Json = '{"version":2,"groups":{},"retired":{}}'; Pattern = 'Invalid tests/suites.json schema' },
    @{ Json = '{"version":1,"groups":[],"retired":{}}'; Pattern = 'Invalid tests/suites.json schema' },
    @{ Json = '{"version":1,"groups":{},"retired":[]}'; Pattern = 'Invalid tests/suites.json schema' },
    @{ Json = '{"version":1,"groups":{"quick":[],"integration":[],"slow":[]},"retired":{}}'; Pattern = 'Catalog groups must be exactly' },
    @{ Json = '{"version":1,"groups":{"quick":[],"integration":[],"slow":[],"assets":[],"typo":[]},"retired":{}}'; Pattern = 'Catalog groups must be exactly' },
    @{ Json = '{"version":1,"groups":{"quick":"test_alpha","integration":[],"slow":[],"assets":[]},"retired":{}}'; Pattern = 'Catalog group must be an array' },
    @{ Json = '{"version":1,"groups":{"quick":[null],"integration":[],"slow":[],"assets":[]},"retired":{}}'; Pattern = 'Invalid catalog test name' },
    @{ Json = '{"version":1,"groups":{"quick":[""],"integration":[],"slow":[],"assets":[]},"retired":{}}'; Pattern = 'Invalid catalog test name' },
    @{ Json = '{"version":1,"groups":{"quick":["../test_alpha"],"integration":[],"slow":[],"assets":[]},"retired":{}}'; Pattern = 'Invalid catalog test name' },
    @{ Json = '{"version":1,"groups":{"quick":[],"integration":[],"slow":[],"assets":[]},"retired":{"test_old":" "}}'; Pattern = 'Retired tests require a valid name and a reason' },
    @{ Json = '{"version":1,"groups":{"quick":[],"integration":[],"slow":[],"assets":[]},"retired":{"test_old":true}}'; Pattern = 'Retired tests require a valid name and a reason' },
    @{ Json = '{"version":1,"groups":{"quick":[],"integration":[],"slow":[],"assets":[]},"retired":{"../test_old":"Invalid path."}}'; Pattern = 'Retired tests require a valid name and a reason' }
)
foreach ($case in $schemaCases) {
    $case.Json | Set-Content -LiteralPath (Join-Path $schemaRoot 'tests/suites.json') -Encoding UTF8
    Assert-Rejected $schemaRoot @{} $case.Pattern
}

# Stub only Git metadata inside this script's scope, avoiding a dependency on an
# initialized scratch repository. The runner still uses actual process launches.
function git {
    if ($args -contains 'rev-parse') { 'runner-self-test-commit' }
}

if ($env:OS -eq 'Windows_NT') {
    $executionRoot = New-Fixture 'execution project with spaces'
    # Replace this fixture's dummy catalog and files only. Never touch live tests.
    Get-ChildItem -LiteralPath (Join-Path $executionRoot 'tests') -Filter 'test_*.gd' -File | Remove-Item
    $executionNames = @('test_01_pass', 'test_02_exit', 'test_03_script', 'test_04_nomarker', 'test_05_timeout', 'test_06_certificate', 'test_07_after')
    foreach ($name in $executionNames) { '# Mock execution case' | Set-Content -LiteralPath (Join-Path $executionRoot "tests/$name.gd") }
    Write-Catalog $executionRoot @{ quick = $executionNames; integration = @(); slow = @(); assets = @() } @{}
    '# Pretend an import already completed' | Set-Content -LiteralPath (Join-Path $executionRoot '.godot/global_script_class_cache.cfg')
    $mock = Join-Path $executionRoot 'mock-godot.cmd'
    @'
param([string]$PidFile, [string]$FinishedFile)
$PID | Set-Content -LiteralPath $PidFile
Start-Sleep -Seconds 12
'A timeout descendant survived' | Set-Content -LiteralPath $FinishedFile
'@ | Set-Content -LiteralPath (Join-Path $executionRoot 'timeout-child.ps1') -Encoding ASCII
    @'
@echo off
setlocal
if "%~1"=="--version" (
  echo 4.7.2.stable.runner-self-test
  exit /b 0
)
set "log="
set "test="
set "mockroot=%~dp0"
:arguments
if "%~1"=="" goto run
if "%~1"=="--log-file" set "log=%~2"
if "%~1"=="-s" set "test=%~2"
shift
goto arguments
:run
if not defined log exit /b 99
echo %cmdcmdline% > "%log%.args"
if "%test%"=="res://tests/test_02_exit.gd" (
  echo PASS: misleading marker > "%log%"
  exit /b 7
)
if "%test%"=="res://tests/test_03_script.gd" (
  echo SCRIPT ERROR: intentional mock error > "%log%"
  echo PASS: misleading marker >> "%log%"
  exit /b 0
)
if "%test%"=="res://tests/test_04_nomarker.gd" (
  echo Finished without a marker > "%log%"
  exit /b 0
)
if "%test%"=="res://tests/test_05_timeout.gd" (
  echo Waiting > "%log%"
  start "" /b "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%mockroot%timeout-child.ps1" "%mockroot%timeout-child.pid" "%mockroot%timeout-child.finished"
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "Start-Sleep -Seconds 20"
  exit /b 0
)
if "%test%"=="res://tests/test_06_certificate.gd" (
  echo ERROR: Failed to read the root certificate store. >> "%log%"
)
if "%test%"=="res://tests/main_scene_smoke.gd" (
  if exist "%mockroot%bad-smoke" (
    echo PASS: unrelated test > "%log%"
  ) else (
    echo PASS: WORLD_READY_FOR_PLAY generation=7 > "%log%"
  )
  exit /b 0
)
if not defined test (
  echo Import complete > "%log%"
  exit /b 0
)
echo PASS: mock check >> "%log%"
exit /b 0
'@ | Set-Content -LiteralPath $mock -Encoding ASCII

    function Invoke-MockRun([hashtable]$Parameters) {
        $Parameters['Godot'] = $mock
        $Parameters['TimeoutSeconds'] = 2
        $before = @(Get-ChildItem -LiteralPath (Join-Path $executionRoot '.godot') -Directory -ErrorAction SilentlyContinue | Where-Object Name -eq 'test-logs' | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory } | ForEach-Object FullName)
        $result = Invoke-Runner $executionRoot $Parameters
        $directories = @(Get-ChildItem -LiteralPath (Join-Path $executionRoot '.godot/test-logs') -Directory | Where-Object { $_.FullName -notin $before })
        Assert-True ($directories.Count -eq 1) 'Each execution must create one unique report directory'
        $reportRoot = $directories[0].FullName
        $report = Get-Content -LiteralPath (Join-Path $reportRoot 'results.json') -Raw | ConvertFrom-Json
        return [PSCustomObject]@{ Invocation = $result; Report = $report; Root = $reportRoot }
    }

    $run = Invoke-MockRun @{ SkipImport = $true }
    Assert-True ($run.Invocation.Failure -match '4 checks failed') "Aggregate failure expected, got '$($run.Invocation.Failure)'"
    Assert-True (($run.Report.results.status -join ',') -eq 'PASS,FAIL,FAIL,FAIL,TIMEOUT,PASS,PASS') 'Failures and timeout must not prevent later checks'
    Assert-True ($run.Report.results[1].exit_code -eq 7) 'Nonzero exit code must override PASS marker'
    Assert-True ($run.Report.results[2].detail -match 'SCRIPT ERROR:') 'Script errors must override PASS marker'
    Assert-True ($run.Report.results[3].detail -eq 'Missing PASS marker') 'Successful exit without PASS marker must fail'
    Assert-True ($run.Report.results[4].detail -match 'Exceeded 2 seconds') 'Timeout must record its deadline'
    $childPidFile = Join-Path $executionRoot 'timeout-child.pid'
    Assert-True (Test-Path -LiteralPath $childPidFile) 'Timeout regression must actually start a descendant process'
    $timeoutChildPid = [int](Get-Content -LiteralPath $childPidFile -Raw).Trim()
    Assert-True ($null -eq (Get-Process -Id $timeoutChildPid -ErrorAction SilentlyContinue)) 'Timeout must terminate the launched process and its descendant'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $executionRoot 'timeout-child.finished'))) 'Timeout descendant must not finish its delayed work'
    Assert-True ($run.Report.selected.Count -eq 7 -and $run.Report.results.Count -eq 7) 'Report must preserve selection and every completed outcome'
    Assert-True (@(Import-Csv -LiteralPath (Join-Path $run.Root 'timings.csv')).Count -eq 7) 'CSV must contain every outcome'
    Assert-True ((Get-Content -LiteralPath (Join-Path $run.Root 'manifest.txt') -Raw) -match 'Import: False') 'Manifest must record skipped import'
    Assert-True ((Get-Content -LiteralPath ($run.Report.results[0].log + '.args') -Raw) -match '--fixed-fps 60') 'Default execution must request fixed FPS'
    foreach ($row in $run.Report.results) { Assert-True (Test-Path -LiteralPath $row.log) "Missing check log: $($row.name)" }

    $fast = Invoke-MockRun @{ SkipImport = $true; FailFast = $true; Smoke = $true }
    Assert-True ($fast.Invocation.Failure -match '1 checks failed') 'FailFast must still signal failure'
    Assert-True (($fast.Report.results.name -join ',') -eq 'test_01_pass,test_02_exit') 'FailFast must stop later checks and smoke'
    Assert-True ($fast.Report.selected.Count -eq 8) 'FailFast report must retain the full requested selection'

    $realTimeRun = Invoke-MockRun @{ TestFilter = @('test_01_pass.gd'); RealTime = $true }
    Assert-True ($null -eq $realTimeRun.Invocation.Failure) "Import and RealTime execution failed: $($realTimeRun.Invocation.Failure)"
    Assert-True (($realTimeRun.Report.results.name -join ',') -eq 'import,test_01_pass') 'Import must run before tests'
    Assert-True ($realTimeRun.Report.real_time -eq $true) 'Report must record RealTime mode'
    Assert-True ((Get-Content -LiteralPath ($realTimeRun.Report.results[1].log + '.args') -Raw) -notmatch '--fixed-fps') 'RealTime must omit fixed FPS'

    $smokeRun = Invoke-MockRun @{ Suite = 'smoke'; SkipImport = $true }
    Assert-True ($null -eq $smokeRun.Invocation.Failure -and $smokeRun.Report.results[0].status -eq 'PASS') 'Smoke must recognize the world readiness marker'
    'Reject a generic PASS marker' | Set-Content -LiteralPath (Join-Path $executionRoot 'bad-smoke')
    $badSmokeRun = Invoke-MockRun @{ Suite = 'smoke'; SkipImport = $true }
    Assert-True ($badSmokeRun.Invocation.Failure -match '1 checks failed' -and $badSmokeRun.Report.results[0].detail -eq 'Missing PASS marker') 'Smoke must reject generic PASS markers'
} else {
    Write-Host 'Skipping Windows batch mock execution checks on this OS.'
}

Write-Host "PASS: runner self-tests ($script:assertions assertions). Scratch evidence: $scratchRoot"
