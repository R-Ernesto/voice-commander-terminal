# hotkey-listener.ps1
# Global hotkey registration via Win32 RegisterHotKey / UnregisterHotKey
# Uses a hidden window message loop to receive WM_HOTKEY messages.

if (-not ([System.Management.Automation.PSTypeName]'HotKeyAPI').Type) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class HotKeyAPI {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    public static extern bool PeekMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax, uint wRemoveMsg);

    [DllImport("user32.dll")]
    public static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    public static extern IntPtr DispatchMessage(ref MSG lpMsg);

    public const int WM_HOTKEY = 0x0312;
    public const uint PM_REMOVE = 0x0001;

    // Modifier constants
    public const uint MOD_ALT     = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT   = 0x0004;
    public const uint MOD_WIN     = 0x0008;

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int x;
        public int y;
    }
}
"@
}

# Map of key names to virtual key codes
$script:VKeyMap = @{
    "0" = 0x30; "1" = 0x31; "2" = 0x32; "3" = 0x33; "4" = 0x34
    "5" = 0x35; "6" = 0x36; "7" = 0x37; "8" = 0x38; "9" = 0x39
    "A" = 0x41; "B" = 0x42; "C" = 0x43; "D" = 0x44; "E" = 0x45
    "F" = 0x46; "G" = 0x47; "H" = 0x48; "I" = 0x49; "J" = 0x4A
    "K" = 0x4B; "L" = 0x4C; "M" = 0x4D; "N" = 0x4E; "O" = 0x4F
    "P" = 0x50; "Q" = 0x51; "R" = 0x52; "S" = 0x53; "T" = 0x54
    "U" = 0x55; "V" = 0x56; "W" = 0x57; "X" = 0x58; "Y" = 0x59; "Z" = 0x5A
    "F1" = 0x70; "F2" = 0x71; "F3" = 0x72; "F4" = 0x73; "F5" = 0x74
    "F6" = 0x75; "F7" = 0x76; "F8" = 0x77; "F9" = 0x78; "F10" = 0x79
    "F11" = 0x7A; "F12" = 0x7B
    "Space" = 0x20; "Enter" = 0x0D; "Escape" = 0x1B; "Tab" = 0x09
}

function Parse-HotkeyString {
    <#
    .SYNOPSIS
    Parses a hotkey string like "Ctrl+Alt+1" into modifier flags and virtual key code.
    #>
    param([string]$HotkeyString)

    $parts = $HotkeyString -split '\+'
    [uint32]$modifiers = 0
    [uint32]$vk = 0

    foreach ($part in $parts) {
        $trimmed = $part.Trim()
        switch ($trimmed.ToLower()) {
            "ctrl"    { $modifiers = $modifiers -bor [HotKeyAPI]::MOD_CONTROL }
            "control" { $modifiers = $modifiers -bor [HotKeyAPI]::MOD_CONTROL }
            "alt"     { $modifiers = $modifiers -bor [HotKeyAPI]::MOD_ALT }
            "shift"   { $modifiers = $modifiers -bor [HotKeyAPI]::MOD_SHIFT }
            "win"     { $modifiers = $modifiers -bor [HotKeyAPI]::MOD_WIN }
            default {
                $key = $trimmed.ToUpper()
                if ($script:VKeyMap.ContainsKey($key)) {
                    $vk = $script:VKeyMap[$key]
                } else {
                    Write-Warning "Unknown key: $trimmed"
                }
            }
        }
    }

    return @{ Modifiers = $modifiers; VirtualKey = $vk }
}

function Register-GlobalHotKey {
    <#
    .SYNOPSIS
    Registers a global hotkey. Returns $true on success.
    #>
    param(
        [int]$Id,
        [string]$HotkeyString
    )

    $parsed = Parse-HotkeyString -HotkeyString $HotkeyString
    if ($parsed.VirtualKey -eq 0) {
        Write-Error "Failed to parse hotkey: $HotkeyString"
        return $false
    }

    $result = [HotKeyAPI]::RegisterHotKey([IntPtr]::Zero, $Id, $parsed.Modifiers, $parsed.VirtualKey)
    if (-not $result) {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Error "RegisterHotKey failed for '$HotkeyString' (id=$Id). Win32 error: $err"
        return $false
    }

    return $true
}

function Unregister-GlobalHotKey {
    <#
    .SYNOPSIS
    Unregisters a previously registered global hotkey.
    #>
    param([int]$Id)

    [HotKeyAPI]::UnregisterHotKey([IntPtr]::Zero, $Id) | Out-Null
}

function Wait-ForHotKey {
    <#
    .SYNOPSIS
    Polls for a WM_HOTKEY message. Returns the hotkey ID if one is received, or -1 if none.
    Non-blocking: use in a loop with Start-Sleep for a responsive message pump.
    #>
    $msg = New-Object HotKeyAPI+MSG

    if ([HotKeyAPI]::PeekMessage([ref]$msg, [IntPtr]::Zero, [HotKeyAPI]::WM_HOTKEY, [HotKeyAPI]::WM_HOTKEY, [HotKeyAPI]::PM_REMOVE)) {
        return [int]$msg.wParam
    }

    return -1
}
