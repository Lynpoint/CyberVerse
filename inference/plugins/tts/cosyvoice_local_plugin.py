import logging
from pathlib import Path
from typing import AsyncIterator

import numpy as np

from inference.core.types import AudioChunk, PluginConfig, TTSRequestConfig
from inference.plugins.tts.base import AudioRechunker, TTSPlugin

logger = logging.getLogger(__name__)

# Endpoints of CosyVoice's FastAPI server (runtime/python/fastapi/server.py).
_MODES = ("zero_shot", "cross_lingual", "instruct2", "sft")
_PROMPT_WAV_MODES = ("zero_shot", "cross_lingual", "instruct2")


def _parse_bool(value) -> bool:
    if isinstance(value, str):
        return value.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(value)


class CosyVoiceLocalTTSPlugin(TTSPlugin):
    """TTS through a self-hosted CosyVoice FastAPI server.

    The server streams raw mono int16 PCM at the model's sample rate
    (24000 Hz for CosyVoice2/3, 22050 Hz for CosyVoice-300M) with no header.
    Each sentence is synthesized, resampled to 16 kHz and rechunked for the
    avatar pipeline, like the other TTS plugins.
    """

    name = "tts.cosyvoice_local"

    def __init__(self) -> None:
        self.base_url = "http://127.0.0.1:50000"
        self.mode = "zero_shot"
        self.spk_id = ""
        self.prompt_text = ""
        self.prompt_wav = ""
        self.instruct_text = ""
        self.use_speaking_style_instruct = False
        self.sample_rate = 24000
        self.target_sample_rate = 16000
        self.timeout_seconds = 60.0
        self.client = None
        self._prompt_wav_bytes: bytes | None = None
        self.rechunker = AudioRechunker()

    async def initialize(self, config: PluginConfig) -> None:
        import httpx

        params = config.params
        self.base_url = str(params.get("base_url") or self.base_url).rstrip("/")
        self.mode = str(params.get("mode", self.mode))
        if self.mode not in _MODES:
            raise ValueError(f"CosyVoice mode must be one of {_MODES}, got {self.mode!r}")
        self.spk_id = str(params.get("spk_id", "") or "")
        self.prompt_text = str(params.get("prompt_text", "") or "")
        self.prompt_wav = str(params.get("prompt_wav", "") or "")
        self.instruct_text = str(params.get("instruct_text", "") or "")
        self.use_speaking_style_instruct = _parse_bool(
            params.get("use_speaking_style_instruct", False)
        )
        self.sample_rate = int(params.get("sample_rate", self.sample_rate))
        self.target_sample_rate = int(params.get("target_sample_rate", self.target_sample_rate))
        self.timeout_seconds = float(params.get("timeout_seconds", self.timeout_seconds))

        # Loaded once; a missing file only fails the sessions that use this provider.
        self._prompt_wav_bytes = None
        if self.prompt_wav:
            path = Path(self.prompt_wav).expanduser()
            if path.is_file():
                self._prompt_wav_bytes = path.read_bytes()
            else:
                logger.warning("CosyVoice prompt_wav not found: %s", path)

        self.client = httpx.AsyncClient(
            base_url=self.base_url, timeout=httpx.Timeout(self.timeout_seconds)
        )
        self.rechunker = AudioRechunker(chunk_samples=17920, sample_rate=self.target_sample_rate)

    async def synthesize_stream(
        self,
        text_stream: AsyncIterator[str],
        request_config: TTSRequestConfig | None = None,
    ) -> AsyncIterator[AudioChunk]:
        rechunker = AudioRechunker(
            chunk_samples=self.rechunker.chunk_samples,
            sample_rate=self.rechunker.sample_rate,
        )
        async for sentence in text_stream:
            if not sentence.strip():
                continue
            try:
                pcm = await self._synthesize(sentence, request_config)
            except Exception:
                logger.exception("CosyVoice TTS failed for: %s", sentence[:50])
                continue
            if not pcm:
                continue
            audio = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
            audio = self._resample(audio, self.sample_rate, self.target_sample_rate)
            for chunk in rechunker.feed(audio):
                yield chunk

        final_chunk = rechunker.flush()
        if final_chunk:
            yield final_chunk

    def _request(
        self, text: str, request_config: TTSRequestConfig | None
    ) -> tuple[str, dict[str, str], dict | None]:
        mode = self.mode
        instruct_text = self.instruct_text
        style = (request_config.speaking_style if request_config else "") or ""
        if self.use_speaking_style_instruct and style.strip():
            # instruct2 voices the prompt speaker in the character's described style.
            mode, instruct_text = "instruct2", style.strip()

        form: dict[str, str] = {"tts_text": text}
        if mode == "sft":
            voice = (request_config.voice if request_config else "") or self.spk_id
            if not voice:
                raise ValueError("CosyVoice sft mode needs spk_id or a request voice")
            form["spk_id"] = voice
        if mode == "zero_shot":
            form["prompt_text"] = self.prompt_text
        if mode == "instruct2":
            form["instruct_text"] = instruct_text

        files = None
        if mode in _PROMPT_WAV_MODES:
            if self._prompt_wav_bytes is None:
                raise ValueError(f"CosyVoice {mode} mode needs a readable prompt_wav")
            files = {"prompt_wav": ("prompt.wav", self._prompt_wav_bytes, "audio/wav")}
        return f"/inference_{mode}", form, files

    async def _synthesize(self, text: str, request_config: TTSRequestConfig | None) -> bytes:
        if self.client is None:
            raise RuntimeError("CosyVoice TTS plugin is not initialized")
        path, form, files = self._request(text, request_config)
        buffer = bytearray()
        async with self.client.stream("POST", path, data=form, files=files) as response:
            response.raise_for_status()
            async for part in response.aiter_bytes():
                buffer.extend(part)
        # Drop a trailing odd byte so the buffer stays int16-aligned.
        if len(buffer) % 2:
            del buffer[-1]
        return bytes(buffer)

    @staticmethod
    def _resample(audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
        if orig_sr == target_sr or len(audio) == 0:
            return audio
        from math import gcd

        from scipy.signal import resample_poly

        g = gcd(orig_sr, target_sr)
        return resample_poly(audio, target_sr // g, orig_sr // g).astype(np.float32)

    async def shutdown(self) -> None:
        if self.client is not None:
            await self.client.aclose()
            self.client = None
        self.rechunker.reset()
