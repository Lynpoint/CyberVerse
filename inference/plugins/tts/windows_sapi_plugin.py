import asyncio
import logging
import os
import tempfile
import wave
from math import gcd
from pathlib import Path
from typing import AsyncIterator

import numpy as np

from inference.core.types import AudioChunk, PluginConfig, TTSRequestConfig
from inference.plugins.tts.base import AudioRechunker, TTSPlugin

logger = logging.getLogger(__name__)


class WindowsSapiTTSPlugin(TTSPlugin):
    """Offline text-to-speech using the installed Windows SAPI voices."""

    name = "tts.windows_sapi"

    def __init__(self) -> None:
        self.voice = ""
        self.rate = 180

    async def initialize(self, config: PluginConfig) -> None:
        if os.name != "nt":
            raise RuntimeError("Windows SAPI TTS is available only on Windows")
        self.voice = str(config.params.get("voice", ""))
        self.rate = int(config.params.get("rate", 180))

    async def synthesize_stream(
        self,
        text_stream: AsyncIterator[str],
        request_config: TTSRequestConfig | None = None,
    ) -> AsyncIterator[AudioChunk]:
        voice = (request_config.voice if request_config else "") or self.voice
        rechunker = AudioRechunker(chunk_samples=17920, sample_rate=16000)
        async for text in text_stream:
            if not text.strip():
                continue
            audio = await asyncio.to_thread(self._synthesize, text, voice)
            for chunk in rechunker.feed(audio):
                yield chunk

        final_chunk = rechunker.flush()
        if final_chunk:
            yield final_chunk

    def _synthesize(self, text: str, preferred_voice: str) -> np.ndarray:
        import pyttsx3

        output_path = ""
        engine = pyttsx3.init()
        try:
            try:
                if preferred_voice and preferred_voice.lower() != "default":
                    preferred_voice = preferred_voice.casefold()
                    for voice in engine.getProperty("voices"):
                        if preferred_voice in f"{voice.id} {voice.name}".casefold():
                            engine.setProperty("voice", voice.id)
                            break
                engine.setProperty("rate", self.rate)
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as output:
                    output_path = output.name
                engine.save_to_file(text, output_path)
                engine.runAndWait()
            finally:
                engine.stop()

            with wave.open(output_path, "rb") as audio_file:
                channels = audio_file.getnchannels()
                sample_rate = audio_file.getframerate()
                sample_width = audio_file.getsampwidth()
                audio_data = audio_file.readframes(audio_file.getnframes())
            if sample_width != 2:
                raise RuntimeError(
                    f"Windows SAPI returned unsupported PCM sample width: {sample_width}"
                )
            samples = np.frombuffer(audio_data, dtype="<i2").astype(np.float32)
            if channels > 1:
                samples = samples.reshape(-1, channels).mean(axis=1)
            samples /= 32768.0
            if sample_rate != 16000:
                divisor = gcd(sample_rate, 16000)
                from scipy.signal import resample_poly

                samples = resample_poly(
                    samples,
                    16000 // divisor,
                    sample_rate // divisor,
                ).astype(np.float32)
            return samples
        finally:
            if output_path:
                Path(output_path).unlink(missing_ok=True)

    async def shutdown(self) -> None:
        logger.info("Windows SAPI TTS plugin shut down")
