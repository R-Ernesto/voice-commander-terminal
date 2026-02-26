# shortcut-service.ps1
# Main service: loads config, registers global hotkeys, runs message loop,
# and dispatches actions (type text or quit).
# MUST run in an interactive process (not Start-Job) for SendInput to work.

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.json")
)

$ErrorActionPreference = "Stop"
$script:LogFile = Join-Path $PSScriptRoot "service.log"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Write-Host $line -ForegroundColor $Color
    Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
}

# Clear previous log
"" | Set-Content $script:LogFile -ErrorAction SilentlyContinue

# Load library modules
. (Join-Path $PSScriptRoot "lib\hotkey-listener.ps1")
. (Join-Path $PSScriptRoot "lib\text-injector.ps1")

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    Write-Log "ERROR: Config not found: $ConfigPath" "Red"
    exit 1
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$shortcuts = $config.shortcuts

if (-not $shortcuts -or $shortcuts.Count -eq 0) {
    Write-Log "ERROR: No shortcuts defined in config." "Red"
    exit 1
}

Write-Log "=== Voice Commander - Shortcut Service ===" "Cyan"
Write-Log "Config: $ConfigPath"
Write-Log "Log: $script:LogFile"

# --- Register hotkeys ---
$registered = @()
for ($i = 0; $i -lt $shortcuts.Count; $i++) {
    $sc = $shortcuts[$i]
    $id = $i + 1

    $success = Register-GlobalHotKey -Id $id -HotkeyString $sc.hotkey
    if ($success) {
        Write-Log "  REGISTERED [$($sc.hotkey)] -> $($sc.label) (action=$($sc.action))" "Green"
        $registered += $id
    } else {
        Write-Log "  FAILED [$($sc.hotkey)] -> $($sc.label)" "Red"
    }
}

if ($registered.Count -eq 0) {
    Write-Log "ERROR: No hotkeys registered. Exiting." "Red"
    exit 1
}

Write-Log "$($registered.Count) hotkeys registered." "Green"
Write-Log "Service running. Press $($shortcuts[-1].hotkey) to quit." "Yellow"
Write-Log "--- Waiting for hotkeys ---"

# --- Message loop ---
$running = $true
try {
    while ($running) {
        $hotkeyId = Wait-ForHotKey

        if ($hotkeyId -ge 1 -and $hotkeyId -le $shortcuts.Count) {
            $sc = $shortcuts[$hotkeyId - 1]
            # Capture target window handle IMMEDIATELY (before focus can shift)
            $targetHwnd = Get-ForegroundWindowHandle
            $fgTitle = Get-ForegroundWindowTitle

            switch ($sc.action) {
                "type" {
                    Write-Log "HOTKEY: $($sc.label) [$($sc.hotkey)] -> target: '$fgTitle' (hwnd=$targetHwnd)" "Cyan"
                    # Delay to let the user release modifier keys
                    Start-Sleep -Milliseconds 200
                    Write-Log "  Injecting $($sc.text.TrimEnd().Length) chars..." "DarkGray"
                    Send-TextToWindow -Text $sc.text -WindowHandle $targetHwnd
                    Write-Log "  Done." "Green"
                }
                "quit" {
                    Write-Log "QUIT requested via $($sc.hotkey)" "Yellow"
                    $running = $false
                }
                default {
                    Write-Log "UNKNOWN action: $($sc.action)" "Red"
                }
            }
        }

        Start-Sleep -Milliseconds 50
    }
}
finally {
    Write-Log "Cleaning up hotkeys..." "DarkGray"
    foreach ($id in $registered) {
        Unregister-GlobalHotKey -Id $id
    }
    Write-Log "Shortcut service stopped." "Yellow"
}
