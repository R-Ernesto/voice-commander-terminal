# voice-poll.ps1
# Polls for signal.json written by the Python voice sidecar.
# Returns a hashtable with {Hwnd, Text, AutoSubmit, ...} or $null if no new signal.

$script:LastSignalTimestamp = 0

function Poll-VoiceSignal {
    param(
        [Parameter(Mandatory)]
        [string]$SignalPath
    )

    if (-not (Test-Path $SignalPath)) {
        return $null
    }

    try {
        $raw = Get-Content $SignalPath -Raw -ErrorAction Stop
        $data = $raw | ConvertFrom-Json

        # Skip if we already processed this timestamp
        if ($data.timestamp -le $script:LastSignalTimestamp) {
            return $null
        }

        $script:LastSignalTimestamp = $data.timestamp

        # Delete the signal file after reading
        Remove-Item $SignalPath -Force -ErrorAction SilentlyContinue

        return @{
            Hwnd       = [IntPtr]::new([long]$data.hwnd)
            Text       = $data.text
            Language   = $data.language
            AudioSec   = $data.audio_sec
            LatencyMs  = $data.latency_ms
            AutoSubmit = $data.auto_submit
            Timestamp  = $data.timestamp
        }
    }
    catch {
        # File might be mid-write, skip this cycle
        return $null
    }
}
