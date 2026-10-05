param(
    [ValidateRange(1024,65535)][int]$Port = 8000,
    [string]$Python,
    [string]$ComfyRuntime,
    [string]$LegacyRoot
)
$ErrorActionPreference = 'Stop'
$pixalRoot = $PSScriptRoot
$pixalApps = Split-Path $pixalRoot -Parent
if (-not $LegacyRoot) { $LegacyRoot = Join-Path $pixalApps 'Pixal3D-API' }
if (-not $Python) { $Python = Join-Path $LegacyRoot '.venv\Scripts\python.exe' }
if (-not $ComfyRuntime) { $ComfyRuntime = Join-Path $pixalApps 'ComfyUI\pixal3d-runtime' }
if (-not (Test-Path -LiteralPath $Python)) { throw 'Pass -Python with an environment containing requirements.txt dependencies.' }
$pixalDeployment = Join-Path $pixalRoot 'deployment'
New-Item -ItemType Directory -Force -Path $pixalDeployment | Out-Null
$env:PIXAL3D_LEGACY_ROOT = $LegacyRoot
$env:PIXAL3D_COMFY = 'http://127.0.0.1:8188'
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    $pixalHealth = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 5
    if ($pixalHealth.service -ne 'pixal3d-api-v2') { throw "Port $Port belongs to another service. Stop its own API first." }
    Write-Output "Already running: http://127.0.0.1:$Port/docs"
    exit 0
}
function Quote-PixalArgument([string]$Value) { return '"' + $Value.Replace('"','\"') + '"' }
if (-not (Get-NetTCPConnection -LocalPort 8188 -State Listen -ErrorAction SilentlyContinue)) {
    $pixalComfyPython = Join-Path $ComfyRuntime '.venv\Scripts\python.exe'
    $pixalModelConfig = Join-Path $LegacyRoot 'deployment\extra_model_paths.yaml'
    if (-not (Test-Path -LiteralPath $pixalComfyPython) -or -not (Test-Path -LiteralPath $pixalModelConfig)) {
        throw 'Existing ComfyUI runtime/model configuration is missing. Start your ComfyUI backend on 8188 first.'
    }
    $pixalInputs = Join-Path $pixalRoot 'inputs'
    New-Item -ItemType Directory -Force -Path $pixalInputs | Out-Null
    $pixalComfyOutput = Join-Path $pixalApps 'ComfyUI\output\pixal3d'
    $pixalComfyArgs = @('-u','main.py','--listen','127.0.0.1','--port','8188','--disable-all-custom-nodes','--offline',
        '--extra-model-paths-config',(Quote-PixalArgument $pixalModelConfig),'--output-directory',(Quote-PixalArgument $pixalComfyOutput),
        '--input-directory',(Quote-PixalArgument $pixalInputs),'--reserve-vram','1.0')
    $pixalBackendProcess = Start-Process -FilePath $pixalComfyPython -ArgumentList $pixalComfyArgs -WorkingDirectory $ComfyRuntime -WindowStyle Hidden -RedirectStandardOutput (Join-Path $pixalDeployment 'comfy.stdout.log') -RedirectStandardError (Join-Path $pixalDeployment 'comfy.stderr.log') -PassThru
    $pixalBackendProcess.Id | Set-Content -LiteralPath (Join-Path $pixalDeployment 'comfy.pid')
}
$pixalReady = $false
for ($pixalAttempt = 0; $pixalAttempt -lt 60; $pixalAttempt++) {
    try {
        Invoke-RestMethod "$env:PIXAL3D_COMFY/system_stats" -TimeoutSec 3 | Out-Null
        $pixalReady = $true
        break
    } catch { Start-Sleep -Seconds 1 }
}
if (-not $pixalReady) { throw 'ComfyUI is not ready. Inspect deployment/comfy.stderr.log.' }
$pixalApiProcess = Start-Process -FilePath $Python -ArgumentList '-u','-m','uvicorn','app:app','--host','127.0.0.1','--port',"$Port" -WorkingDirectory $pixalRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $pixalDeployment "api-$Port.stdout.log") -RedirectStandardError (Join-Path $pixalDeployment "api-$Port.stderr.log") -PassThru
$pixalApiProcess.Id | Set-Content -LiteralPath (Join-Path $pixalDeployment "api-$Port.pid")
for ($pixalAttempt = 0; $pixalAttempt -lt 20; $pixalAttempt++) {
    try {
        $pixalHealth = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3
        if ($pixalHealth.service -eq 'pixal3d-api-v2') {
            Write-Output "Asset API V2: http://127.0.0.1:$Port/docs"
            exit 0
        }
    } catch { Start-Sleep -Milliseconds 500 }
}
throw "API startup failed. Inspect deployment/api-$Port.stderr.log."
