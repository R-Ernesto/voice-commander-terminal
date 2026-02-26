# start.ps1
# Entry point for Voice Commander Terminal.
# -ServiceOnly: runs the shortcut service directly in the current process
# Normal mode: launches service as a separate visible process + claude in foreground

param(
    [switch]$ServiceOnly,    # Only run the shortcut service (no claude)
    [string]$ConfigPath      # Optional: custom config path
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$servicePath = Join-Path $scriptDir "shortcut-service.ps1"
$logPath = Join-Path $scriptDir "service.log"

if (-not (Test-Path $servicePath)) {
    Write-Error "shortcut-service.ps1 not found at: $servicePath"
    exit 1
}

Write-Host ""
Write-Host "Voice Commander Terminal" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log file: $logPath" -ForegroundColor DarkGray
Write-Host ""

if ($ServiceOnly) {
    # Run the service directly in the current process (interactive session).
    # This is critical: SendInput only works from an interactive desktop process.
    Write-Host "Running in service-only mode (direct, interactive)." -ForegroundColor Yellow
    Write-Host ""

    $args = @()
    if ($ConfigPath) { $args += "-ConfigPath", $ConfigPath }
    & $servicePath @args
}
else {
    # Launch the service as a separate visible (minimized) PowerShell window.
    # Must be a real window process, NOT Start-Job (which has no desktop access).
    Write-Host "Starting shortcut service in separate window..." -ForegroundColor DarkGray

    $psArgs = "-NoExit -File `"$servicePath`""
    if ($ConfigPath) {
        $psArgs = "-NoExit -File `"$servicePath`" -ConfigPath `"$ConfigPath`""
    }

    $serviceProc = Start-Process powershell -ArgumentList $psArgs `
        -WindowStyle Minimized -PassThru

    Write-Host "Service started (PID: $($serviceProc.Id), minimized window)" -ForegroundColor Green
    Start-Sleep -Seconds 1

    Write-Host ""
    Write-Host "Launching Claude Code..." -ForegroundColor Cyan
    Write-Host "Shortcuts are active. Check service window or $logPath for logs." -ForegroundColor DarkGray
    Write-Host ""

    try {
        claude
    }
    catch {
        Write-Warning "Claude Code exited with error: $_"
    }
    finally {
        Write-Host ""
        Write-Host "Claude Code exited. Cleaning up..." -ForegroundColor DarkGray

        if (-not $serviceProc.HasExited) {
            Stop-Process -Id $serviceProc.Id -Force -ErrorAction SilentlyContinue
            Write-Host "Service process stopped." -ForegroundColor Green
        }
        else {
            Write-Host "Service had already exited." -ForegroundColor DarkGray
        }

        Write-Host "Goodbye!" -ForegroundColor Green
    }
}
