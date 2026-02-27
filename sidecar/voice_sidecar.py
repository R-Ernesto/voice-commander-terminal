"""Voice sidecar entry point. Loads config, warms up Whisper, loops push-to-talk cycles."""

import json
import os
import sys
import time

# Add sidecar directory to path for relative imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)


def load_config() -> dict:
    """Load voice config from project's config.json."""
    defaults = {
        "hotkey": "ctrl+alt+v",
        "whisper_model": "medium",
        "whisper_device": "cuda",
        "whisper_compute_type": "float16",
        "whisper_initial_prompt": "KAPS, Syion, Claude Code, PowerShell, git",
        "auto_submit": True,
        "sample_rate": 16000,
        "channels": 1,
    }
    config_path = os.path.join(PROJECT_DIR, "config.json")
    if os.path.exists(config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if "voice" in data:
            defaults.update(data["voice"])
    return defaults


def main():
    cfg = load_config()
    signal_path = os.path.join(PROJECT_DIR, "signal.json")

    print(f"[voice-sidecar] Hotkey submit: {cfg['hotkey']} (auto-enter)")
    print(f"[voice-sidecar] Hotkey text:   {cfg.get('hotkey_text', 'ctrl+alt+t')} (paste only)")
    print(f"[voice-sidecar] Model: {cfg['whisper_model']} ({cfg['whisper_device']}/{cfg['whisper_compute_type']})")
    print(f"[voice-sidecar] Signal: {signal_path}")

    # Warm up Whisper model
    from stt import load_model
    print("[voice-sidecar] Loading Whisper model...", flush=True)
    t0 = time.perf_counter()
    load_model(cfg)
    elapsed = time.perf_counter() - t0
    print(f"[voice-sidecar] Model loaded ({elapsed:.1f}s)", flush=True)

    from hotkey_handler import PushToTalkHandler
    from signal_writer import write_signal

    handler = PushToTalkHandler(cfg)

    print("[voice-sidecar] Ready. Ctrl+Alt+V=submit, Ctrl+Alt+T=text only.", flush=True)

    while True:
        try:
            # Reload config each cycle (hot-reload prompt changes without restart)
            handler.cfg = load_config()
            result = handler.wait_for_cycle()
            mode = result["mode"]
            auto_submit = mode == "submit"
            print(f"[voice-sidecar] [{mode}] \"{result['text']}\" "
                  f"({result['audio_sec']}s audio, {result['latency_ms']}ms STT, "
                  f"lang={result['language']})", flush=True)

            write_signal(
                signal_path=signal_path,
                hwnd=result["hwnd"],
                text=result["text"],
                language=result["language"],
                audio_sec=result["audio_sec"],
                latency_ms=result["latency_ms"],
                auto_submit=auto_submit,
            )
        except KeyboardInterrupt:
            print("\n[voice-sidecar] Stopped.", flush=True)
            break
        except Exception as e:
            print(f"[voice-sidecar] Error: {e}", flush=True)


if __name__ == "__main__":
    main()
