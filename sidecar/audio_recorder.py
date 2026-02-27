"""Audio capture using sounddevice. Start/stop recording, returns numpy buffer."""

import numpy as np
import sounddevice as sd


class AudioRecorder:
    def __init__(self, sample_rate: int = 16000, channels: int = 1):
        self.sample_rate = sample_rate
        self.channels = channels
        self._buffer: list[np.ndarray] = []
        self._stream: sd.InputStream | None = None
        self._recording = False

    def _callback(self, indata, frames, time_info, status):
        if self._recording:
            self._buffer.append(indata.copy())

    def start(self) -> None:
        """Start capturing audio from the default microphone."""
        if self._recording:
            return
        self._buffer.clear()
        self._recording = True
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype="float32",
            callback=self._callback,
        )
        self._stream.start()

    def stop(self) -> np.ndarray:
        """Stop recording and return the captured audio as float32 array."""
        self._recording = False
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        if self._buffer:
            audio = np.concatenate(self._buffer, axis=0).flatten()
        else:
            audio = np.array([], dtype=np.float32)
        self._buffer.clear()
        return audio
