# text-injector.ps1
# Injects text into the target window via clipboard paste.
# Uses SetForegroundWindow to ensure the correct window gets the paste.

if (-not ([System.Management.Automation.PSTypeName]'TextInjectorAPI').Type) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class TextInjectorAPI {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
}
"@
}

function Get-ForegroundWindowTitle {
    $hwnd = [TextInjectorAPI]::GetForegroundWindow()
    $sb = New-Object System.Text.StringBuilder 256
    [TextInjectorAPI]::GetWindowText($hwnd, $sb, $sb.Capacity) | Out-Null
    return $sb.ToString()
}

function Get-ForegroundWindowHandle {
    return [TextInjectorAPI]::GetForegroundWindow()
}

function Send-TextToWindow {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        [Parameter(Mandatory)]
        [IntPtr]$WindowHandle
    )

    $endsWithNewline = $Text.EndsWith("`n")
    $textToClip = $Text.TrimEnd("`r", "`n")

    # 1. Save old clipboard
    $oldClip = Get-Clipboard -Raw -ErrorAction SilentlyContinue

    # 2. Set clipboard
    Set-Clipboard -Value $textToClip

    # 3. Force focus to the target window
    [TextInjectorAPI]::SetForegroundWindow($WindowHandle) | Out-Null
    Start-Sleep -Milliseconds 150

    # 4. Paste via WScript.Shell
    $wsh = New-Object -ComObject WScript.Shell
    $wsh.SendKeys("^v")
    Start-Sleep -Milliseconds 200

    # 5. Send Enter if needed
    if ($endsWithNewline) {
        $wsh.SendKeys("{ENTER}")
    }

    # 6. Restore clipboard
    Start-Sleep -Milliseconds 300
    if ($oldClip) {
        Set-Clipboard -Value $oldClip -ErrorAction SilentlyContinue
    }
}
