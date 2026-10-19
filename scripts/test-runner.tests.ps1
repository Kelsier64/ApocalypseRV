# Isolated runner checks; no Godot installation or project import needed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$scratchRoot = Join-Path $repositoryRoot ('.godot/runner-self-tests/' + [Guid]::NewGuid().ToString('N') + ' project with spaces')
New-Item -ItemType Directory -Path (Join-Path $scratchRoot 'scripts'), (Join-Path $scratchRoot 'tests'), (Join-Path $scratchRoot '.godot') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test.ps1') -Destination (Join-Path $scratchRoot 'scripts/test.ps1')
'4.7.2' | Set-Content -LiteralPath (Join-Path $scratchRoot '.godot-version')
foreach ($name in @('test_alpha', 'test_bravo')) { '# Fixture' | Set-Content -LiteralPath (Join-Path $scratchRoot "tests/$name.gd") }
$script:assertions = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Self-test failed: $Message" }
    $script:assertions++
}
function Invoke-Runner([hashtable]$Parameters) {
    $failure = $null
    $rows = @()
    try { $rows = @(& (Join-Path $scratchRoot 'scripts/test.ps1') @Parameters 6>$null) }
    catch { $failure = $_.Exception.Message }
    [PSCustomObject]@{ Rows = $rows; Failure = $failure }
}
function Assert-Selection([hashtable]$Parameters, [string[]]$Expected) {
    $Parameters['List'] = $true
    $Parameters['Godot'] = 'runner-self-test-engine-must-not-be-launched'
    $result = Invoke-Runner $Parameters
    Assert-True ($null -eq $result.Failure) "Selection failed: $($result.Failure)"
    Assert-True (($result.Rows.Name -join ',') -ceq ($Expected -join ',')) 'Unexpected test selection'
}
Assert-Selection @{} @('test_alpha', 'test_bravo', 'main-scene')
Assert-Selection @{ TestFilter = @('test_bravo.gd,test_alpha.gd', 'test_a*.gd') } @('test_alpha', 'test_bravo')
Assert-Selection @{ TestFilter = @('test_bravo.gd'); Smoke = $true } @('test_bravo', 'main-scene')
Assert-Selection @{ SmokeOnly = $true } @('main-scene')
foreach ($case in @(
    @{ Parameters = @{ TestFilter = @('test_alpha.gd', 'missing*') }; Pattern = 'No tests discovered' },
    @{ Parameters = @{ TestFilter = @('test_alpha.gd,') }; Pattern = 'cannot be empty' },
    @{ Parameters = @{ TestFilter = @() }; Pattern = 'At least one test filter' },
    @{ Parameters = @{ SmokeOnly = $true; TestFilter = @('test_alpha.gd') }; Pattern = 'cannot be combined' }
)) {
    $case.Parameters['List'] = $true
    $result = Invoke-Runner $case.Parameters
    Assert-True ($result.Failure -match $case.Pattern) "Expected selection rejection: $($case.Pattern)"
}

# Execution cases use a tiny batch engine, including a real timeout descendant.
if ($env:OS -ne 'Windows_NT') { throw 'Runner execution self-tests require Windows' }
function git { if ($args -contains 'rev-parse') { 'runner-self-test' } }
'# Imported fixture' | Set-Content -LiteralPath (Join-Path $scratchRoot '.godot/global_script_class_cache.cfg')
@'
param([string]$PidFile)
$PID | Set-Content -LiteralPath $PidFile
Start-Sleep -Seconds 30
'@ | Set-Content -LiteralPath (Join-Path $scratchRoot 'timeout-child.ps1') -Encoding ASCII
$mock = Join-Path $scratchRoot 'mock-godot.cmd'
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
set /p mode=<"%mockroot%mode.txt"
:arguments
if "%~1"=="" goto run
if "%~1"=="--log-file" set "log=%~2"
if "%~1"=="-s" set "test=%~2"
shift
goto arguments
:run
if not defined log exit /b 99
echo %cmdcmdline% > "%log%.args"
if not defined test (
  if "%mode%"=="import" (
    echo ERROR: broken import > "%log%"
    exit /b 0
  )
  echo Import complete > "%log%"
  exit /b 0
)
if "%test%"=="res://tests/main_scene_smoke.gd" (
  if "%mode%"=="smoke" (
    echo PASS: unrelated test > "%log%"
  ) else (
    echo PASS: WORLD_READY_FOR_PLAY > "%log%"
  )
  exit /b 0
)
if "%mode%"=="exit" (
  echo PASS: misleading marker > "%log%"
  exit /b 7
)
if "%mode%"=="script" (
  echo SCRIPT ERROR: intentional mock error > "%log%"
  echo PASS: misleading marker >> "%log%"
  exit /b 0
)
if "%mode%"=="nomarker" (
  echo Finished without a marker > "%log%"
  exit /b 0
)
if "%mode%"=="empty" exit /b 0
if "%mode%"=="timeout" (
  echo Waiting > "%log%"
  start "" /b "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%mockroot%timeout-child.ps1" "%mockroot%timeout-child.pid"
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "Start-Sleep -Seconds 60"
  exit /b 0
)
echo ERROR: Failed to read the root certificate store. > "%log%"
echo PASS: mock check >> "%log%"
exit /b 0
'@ | Set-Content -LiteralPath $mock -Encoding ASCII

function Invoke-MockRun([string]$Mode, [hashtable]$Parameters) {
    $Mode | Set-Content -LiteralPath (Join-Path $scratchRoot 'mode.txt') -Encoding ASCII
    $Parameters['Godot'] = $mock
    $Parameters['TimeoutSeconds'] = 3
    $reportRoot = Join-Path $scratchRoot '.godot/test-logs'
    $before = @(Get-ChildItem -LiteralPath $reportRoot -Filter results.json -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $result = Invoke-Runner $Parameters
    $reports = @(Get-ChildItem -LiteralPath $reportRoot -Filter results.json -Recurse | Where-Object FullName -notin $before)
    Assert-True ($reports.Count -eq 1) 'Each execution must save its own report'
    [PSCustomObject]@{ Failure = $result.Failure; Report = (Get-Content -LiteralPath $reports[0].FullName -Raw | ConvertFrom-Json) }
}
$run = Invoke-MockRun 'pass' @{}
Assert-True ($null -eq $run.Failure) "Successful run failed: $($run.Failure)"
Assert-True (($run.Report.results.name -join ',') -eq 'import,test_alpha,test_bravo,main-scene') 'Import and every selected check must run in order'
Assert-True (@($run.Report.results | Where-Object status -ne 'PASS').Count -eq 0) 'Success and certificate exception must pass'
Assert-True ((Get-Content -LiteralPath ($run.Report.results[1].log + '.args') -Raw) -match '--fixed-fps 60') 'Default execution must use fixed FPS'
foreach ($case in @(
    @{ Mode = 'exit'; Detail = 'Exit code 7'; Status = 'FAIL' },
    @{ Mode = 'script'; Detail = 'SCRIPT ERROR:'; Status = 'FAIL' },
    @{ Mode = 'nomarker'; Detail = 'Missing PASS marker'; Status = 'FAIL' },
    @{ Mode = 'empty'; Detail = 'Empty engine log'; Status = 'FAIL' },
    @{ Mode = 'timeout'; Detail = 'Exceeded 3 seconds'; Status = 'TIMEOUT' }
)) {
    $run = Invoke-MockRun $case.Mode @{ SkipImport = $true }
    Assert-True ($null -ne $run.Failure -and $run.Report.results[0].status -eq $case.Status -and $run.Report.results[0].detail -match $case.Detail) "Failure was not detected: $($case.Mode)"
    Assert-True ($run.Report.results.Count -eq 1 -and $run.Report.selected.Count -eq 3) 'Failure must stop later tests and smoke while retaining the selection'
}
$childPidFile = Join-Path $scratchRoot 'timeout-child.pid'
Assert-True (Test-Path -LiteralPath $childPidFile) 'Timeout fixture must actually start its descendant'
$timeoutChildPid = [int](Get-Content -LiteralPath $childPidFile -Raw).Trim()
Assert-True ($null -eq (Get-Process -Id $timeoutChildPid -ErrorAction SilentlyContinue)) 'Timeout must terminate its descendant'
$run = Invoke-MockRun 'smoke' @{ SmokeOnly = $true; SkipImport = $true }
Assert-True ($null -ne $run.Failure -and $run.Report.results[0].detail -eq 'Missing PASS marker') 'Smoke must reject a generic PASS marker'
$run = Invoke-MockRun 'import' @{}
Assert-True ($null -ne $run.Failure -and ($run.Report.results.name -join ',') -eq 'import') 'Import errors must stop tests'
$run = Invoke-MockRun 'pass' @{ TestFilter = @('test_alpha.gd'); RealTime = $true; SkipImport = $true }
Assert-True ($null -eq $run.Failure -and $run.Report.metadata.real_time -and -not $run.Report.metadata.import) 'Report must record execution options'
Assert-True ((Get-Content -LiteralPath ($run.Report.results[0].log + '.args') -Raw) -notmatch '--fixed-fps') 'RealTime must omit fixed FPS'
Write-Host "PASS: runner self-tests ($script:assertions assertions). Scratch evidence: $scratchRoot"
