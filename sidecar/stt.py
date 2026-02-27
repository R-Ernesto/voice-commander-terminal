"""Speech-to-text using faster-whisper. Singleton model, adapted from voice-commander."""

import time
from dataclasses import dataclass

import numpy as np
from faster_whisper import WhisperModel


@dataclass
class TranscriptionResult:
    text: str
    language: str
    audio_duration_sec: float
    latency_ms: int


_model: WhisperModel | None = None
_model_cfg: dict | None = None


def load_model(cfg: dict) -> None:
    """Pre-load the Whisper model (call once at startup)."""
    global _model, _model_cfg
    if _model is not None:
        return
    _model_cfg = cfg
    _model = WhisperModel(
        cfg["whisper_model"],
        device=cfg["whisper_device"],
        compute_type=cfg["whisper_compute_type"],
    )


def transcribe(audio: np.ndarray, cfg: dict) -> TranscriptionResult:
    """Transcribe audio buffer to text."""
    global _model
    if _model is None:
        load_model(cfg)

    sample_rate = cfg.get("sample_rate", 16000)
    audio_duration = len(audio) / sample_rate

    t0 = time.perf_counter()
    segments, info = _model.transcribe(
        audio,
        language=None,
        initial_prompt=cfg.get("whisper_initial_prompt", ""),
        vad_filter=True,
    )
    text = " ".join(seg.text.strip() for seg in segments)
    latency_ms = int((time.perf_counter() - t0) * 1000)

    return TranscriptionResult(
        text=text.strip(),
        language=info.language,
        audio_duration_sec=round(audio_duration, 2),
        latency_ms=latency_ms,
    )
