param([string]$Godot = 'godot')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$logDirectory = Join-Path $projectRoot '.godot/test-logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$executable = (Get-Command $Godot -ErrorAction Stop).Source

function Invoke-GodotCheck([string]$Name, [string[]]$ExtraArguments, [bool]$RequirePass = $false) {
    $log = Join-Path $logDirectory ($Name + '.log')
    [IO.File]::WriteAllText($log, '')
    $arguments = @('--headless', '--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $log + '"')) + $ExtraArguments
    $process = Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(120000)) {
        $process.Kill()
        throw "$Name timed out after 120 seconds. See $log"
    }
    $process.Refresh()
    $output = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
    # The restricted Windows environment cannot read the OS certificate store.
    # Ignore only that specific engine diagnostic, never script/runtime errors.
    $errors = $output -split "`n" | Where-Object { $_ -match '(SCRIPT ERROR:|ERROR:|FAIL:|Program crashed)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.' }
    if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output) -or $errors -or ($RequirePass -and $output -notmatch '(?m)^PASS:')) {
        Write-Host $output
        throw "$Name failed (exit $($process.ExitCode)). See $log"
    }
    Write-Host "PASS: $Name"
}

Invoke-GodotCheck 'import' @('--editor', '--import', '--quit')
foreach ($test in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter 'test_*.gd' | Sort-Object Name) {
    $testArguments = @('-s', ('res://tests/' + $test.Name))
    # Long outdoor round trips exceed two minutes of simulated play. Keep
    # normal 60 Hz physics while letting headless rendering run unthrottled.
    if ($test.BaseName -like 'test_outdoor_*') { $testArguments += @('--fixed-fps', '60') }
    Invoke-GodotCheck $test.BaseName $testArguments $true
}
Invoke-GodotCheck 'main-scene' @('--quit-after', '120')
