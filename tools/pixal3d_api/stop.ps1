param([ValidateRange(1024,65535)][int]$Port = 8000, [switch]$Force, [string]$Python)
$ErrorActionPreference = 'Stop'
if (-not $Python) { $Python = Join-Path (Split-Path $PSScriptRoot -Parent) 'Pixal3D-API\.venv\Scripts\python.exe' }
$pixalStopArgs = @((Join-Path $PSScriptRoot 'deployment\stop_api.py'), '--port', "$Port")
if ($Force) { $pixalStopArgs += '--force' }
& $Python @pixalStopArgs
if ($LASTEXITCODE -ne 0) { throw "API stop failed ($LASTEXITCODE)" }
