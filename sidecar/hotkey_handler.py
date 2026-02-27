"""Push-to-talk handler with two modes:
- Ctrl+Alt+V (submit): record → transcribe → auto-submit (Enter)
- Ctrl+Alt+T (text):   record → transcribe → paste only (no Enter)
"""

import ctypes
import threading
import winsound

import keyboard

from audio_recorder import AudioRecorder
from stt import transcribe


user32 = ctypes.windll.user32


class PushToTalkHandler:
    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.sample_rate = cfg.get("sample_rate", 16000)
        self.channels = cfg.get("channels", 1)

        # Two hotkeys, two modes
        hotkey_submit = cfg.get("hotkey", "ctrl+alt+v")
        hotkey_text = cfg.get("hotkey_text", "ctrl+alt+t")
        self._hotkeys = {
            hotkey_submit.split("+")[-1]: {"combo": hotkey_submit, "mode": "submit"},
            hotkey_text.split("+")[-1]:   {"combo": hotkey_text,   "mode": "text"},
        }

        self._recorder = AudioRecorder(self.sample_rate, self.channels)
        self._recording = False
        self._current_mode: str | None = None
        self._hwnd: int = 0
        self._result_event = threading.Event()
        self._result: dict | None = None

    def _on_key_down(self, trigger_key: str, event):
        if self._recording:
            return
        hk = self._hotkeys[trigger_key]
        if not keyboard.is_pressed(hk["combo"]):
            return
        # Capture the foreground window IMMEDIATELY
        self._hwnd = user32.GetForegroundWindow()
        self._current_mode = hk["mode"]
        self._recording = True
        # Beep: recording started (800 Hz, 150ms) — non-blocking
        threading.Thread(target=winsound.Beep, args=(800, 150), daemon=True).start()
        self._recorder.start()

    def _on_key_up(self, trigger_key: str, event):
        if not self._recording:
            return
        # Only stop if the released key matches the mode that started recording
        hk = self._hotkeys[trigger_key]
        if hk["mode"] != self._current_mode:
            return
        self._recording = False
        audio = self._recorder.stop()

        if len(audio) < self.sample_rate * 0.3:
            # Less than 0.3s of audio — ignore (accidental press)
            return

        # Beep: recording stopped (600 Hz, 150ms)
        threading.Thread(target=winsound.Beep, args=(600, 150), daemon=True).start()

        result = transcribe(audio, self.cfg)

        if not result.text:
            return

        self._result = {
            "hwnd": self._hwnd,
            "text": result.text,
            "language": result.language,
            "audio_sec": result.audio_duration_sec,
            "latency_ms": result.latency_ms,
            "mode": self._current_mode,
        }
        self._result_event.set()

    def wait_for_cycle(self) -> dict:
        """Block until a complete press-release-transcribe cycle finishes.
        Returns dict with {hwnd, text, language, audio_sec, latency_ms, mode}."""
        self._result_event.clear()
        self._result = None

        for trigger_key in self._hotkeys:
            keyboard.on_press_key(
                trigger_key,
                lambda e, k=trigger_key: self._on_key_down(k, e),
                suppress=False,
            )
            keyboard.on_release_key(
                trigger_key,
                lambda e, k=trigger_key: self._on_key_up(k, e),
                suppress=False,
            )

        self._result_event.wait()

        keyboard.unhook_all()
        return self._result
