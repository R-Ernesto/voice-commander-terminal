"""Atomic signal file writer. Writes to .tmp then renames to avoid partial reads."""

import json
import os
import time


def write_signal(signal_path: str, hwnd: int, text: str, language: str,
                 audio_sec: float, latency_ms: int, auto_submit: bool) -> None:
    """Write transcription result atomically to signal.json."""
    data = {
        "hwnd": hwnd,
        "text": text,
        "language": language,
        "audio_sec": audio_sec,
        "latency_ms": latency_ms,
        "auto_submit": auto_submit,
        "timestamp": time.time(),
    }
    tmp_path = signal_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    # Atomic rename (on Windows, need to remove target first if it exists)
    if os.path.exists(signal_path):
        os.remove(signal_path)
    os.rename(tmp_path, signal_path)
