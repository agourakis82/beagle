"""
Whisper Voice Transcription
Supports OpenAI API and local Whisper model
"""

import whisper
import os
from typing import Optional
from pydantic import BaseModel

class TranscriptionResult(BaseModel):
    text: str
    language: str
    confidence: float

class WhisperTranscriber:
    def __init__(self, model_size: str = "base", use_api: bool = False):
        """
        Initialize Whisper transcriber
        
        Args:
            model_size: "tiny", "base", "small", "medium", "large"
            use_api: If True, use OpenAI API (requires OPENAI_API_KEY)
        """
        self.use_api = use_api
        
        if use_api:
            self.api_key = os.getenv("OPENAI_API_KEY")
            if not self.api_key:
                raise ValueError("OPENAI_API_KEY not set")
        else:
            self.model = whisper.load_model(model_size)
    
    def transcribe_audio(self, audio_path: str) -> TranscriptionResult:
        """Transcribe audio file to text"""
        if self.use_api:
            return self._transcribe_api(audio_path)
        else:
            return self._transcribe_local(audio_path)
    
    def _transcribe_local(self, audio_path: str) -> TranscriptionResult:
        """Local Whisper model"""
        result = self.model.transcribe(audio_path)
        
        return TranscriptionResult(
            text=result["text"].strip(),
            language=result["language"],
            confidence=self._estimate_confidence(result),
        )
    
    def _transcribe_api(self, audio_path: str) -> TranscriptionResult:
        """OpenAI Whisper API"""
        import openai
        openai.api_key = self.api_key
        
        with open(audio_path, "rb") as audio_file:
            transcript = openai.Audio.transcribe("whisper-1", audio_file)
        
        return TranscriptionResult(
            text=transcript["text"].strip(),
            language=transcript.get("language", "en"),
            confidence=0.95,  # API doesn't provide confidence
        )
    
    def _estimate_confidence(self, result: dict) -> float:
        """Estimate confidence from Whisper result"""
        # Whisper doesn't provide direct confidence, use heuristics
        segments = result.get("segments", [])
        if not segments:
            return 0.8
        
        # Average no_speech_prob (inverted)
        avg_confidence = 1.0 - sum(s.get("no_speech_prob", 0.0) for s in segments) / len(segments)
        return max(0.5, min(1.0, avg_confidence))

def transcribe_audio_json(audio_path: str, use_api: bool = False) -> dict:
    """Python entry point for Rust FFI"""
    transcriber = WhisperTranscriber(use_api=use_api)
    result = transcriber.transcribe_audio(audio_path)
    return result.model_dump()

# CLI for testing
if __name__ == "__main__":
    import sys
    audio_path = sys.argv[1] if len(sys.argv) > 1 else "test_audio.mp3"
    
    transcriber = WhisperTranscriber()
    result = transcriber.transcribe_audio(audio_path)
    
    print(f"\n🎤 Transcription:\n")
    print(f"  Text: {result.text}")
    print(f"  Language: {result.language}")
    print(f"  Confidence: {result.confidence:.2f}")
