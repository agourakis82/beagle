"""
Whisper transcription using optimized implementation
"""
import whisper
import numpy as np
import io


_model = None


def load_model(model_path: str):
    """Load Whisper model."""
    global _model
    _model = whisper.load_model(model_path)


def transcribe(audio_bytes: bytes, sample_rate: int) -> str:
    """
    Transcribe audio bytes to text.

    Args:
        audio_bytes: Raw audio data (PCM)
        sample_rate: Sample rate (Hz)

    Returns:
        Transcribed text
    """
    if _model is None:
        raise RuntimeError("Model not loaded. Call load_model() first.")

    # Convert bytes to numpy array
    audio_array = np.frombuffer(audio_bytes, dtype=np.int16).astype(np.float32) / 32768.0

    # Resample if needed (Whisper expects 16kHz)
    if sample_rate != 16000:
        from scipy import signal
        num_samples = int(len(audio_array) * 16000 / sample_rate)
        audio_array = signal.resample(audio_array, num_samples)

    # Transcribe
    result = _model.transcribe(audio_array, language="en")

    return result["text"].strip()

