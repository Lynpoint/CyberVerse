"""Tests for the self-hosted CosyVoice TTS plugin."""
from urllib.parse import parse_qs

import httpx
import numpy as np
import pytest

from inference.core.types import PluginConfig, TTSRequestConfig
from inference.plugins.tts.cosyvoice_local_plugin import CosyVoiceLocalTTSPlugin


def _pcm(seconds: float, rate: int = 24000) -> bytes:
    samples = int(seconds * rate)
    tone = 0.5 * np.sin(np.linspace(0, 2 * np.pi * 220 * seconds, samples))
    return (tone * 32767).astype(np.int16).tobytes()


class FakeServer:
    """Records CosyVoice FastAPI requests and streams PCM back in odd-sized parts."""

    def __init__(self, pcm: bytes, status: int = 200) -> None:
        self.pcm = pcm
        self.status = status
        self.requests: list[httpx.Request] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.status != 200:
            return httpx.Response(self.status, text="boom")
        pcm = self.pcm

        async def parts():
            for i in range(0, len(pcm), 1001):
                yield pcm[i:i + 1001]

        return httpx.Response(200, content=parts())


async def _plugin(server: FakeServer, tmp_path, **params) -> CosyVoiceLocalTTSPlugin:
    wav = tmp_path / "voice.wav"
    wav.write_bytes(b"RIFF-fake-wav")
    params.setdefault("prompt_wav", str(wav))
    plugin = CosyVoiceLocalTTSPlugin()
    await plugin.initialize(PluginConfig(plugin_name="tts.cosyvoice_local", params=params))
    plugin.client = httpx.AsyncClient(
        base_url=plugin.base_url, transport=httpx.MockTransport(server.handler)
    )
    return plugin


async def _texts(*items: str):
    for item in items:
        yield item


async def _synthesize(plugin, *texts, request_config=None):
    return [c async for c in plugin.synthesize_stream(_texts(*texts), request_config)]


def _form(request: httpx.Request) -> bytes:
    return request.read()


async def test_zero_shot_posts_prompt_and_returns_16k_chunks(tmp_path):
    server = FakeServer(_pcm(2.0))
    plugin = await _plugin(server, tmp_path, prompt_text="你好呀")

    chunks = await _synthesize(plugin, "今天天气不错。", "  ")

    assert len(server.requests) == 1  # blank sentences are skipped
    request = server.requests[0]
    assert request.url.path == "/inference_zero_shot"
    body = _form(request)
    assert "今天天气不错。".encode() in body and "你好呀".encode() in body
    assert b"RIFF-fake-wav" in body
    # 2 s at 24 kHz -> 32000 samples at 16 kHz -> one full 17920 chunk + padded final chunk
    assert [c.is_final for c in chunks] == [False, True]
    assert all(c.sample_rate == 16000 and len(c.data) == 17920 * 4 for c in chunks)
    assert np.abs(np.frombuffer(chunks[0].data, dtype=np.float32)).max() > 0.3


async def test_odd_byte_count_is_trimmed(tmp_path):
    server = FakeServer(_pcm(1.2) + b"\x01")
    plugin = await _plugin(server, tmp_path)

    chunks = await _synthesize(plugin, "hi")

    assert chunks and chunks[-1].is_final


async def test_speaking_style_switches_to_instruct2_when_enabled(tmp_path):
    server = FakeServer(_pcm(0.5))
    plugin = await _plugin(server, tmp_path, use_speaking_style_instruct="true")

    await _synthesize(plugin, "hello", request_config=TTSRequestConfig(speaking_style="用温柔的语气说"))

    request = server.requests[0]
    assert request.url.path == "/inference_instruct2"
    assert "用温柔的语气说".encode() in _form(request)


async def test_speaking_style_is_ignored_by_default(tmp_path):
    server = FakeServer(_pcm(0.5))
    plugin = await _plugin(server, tmp_path)

    await _synthesize(plugin, "hello", request_config=TTSRequestConfig(speaking_style="温柔"))

    assert server.requests[0].url.path == "/inference_zero_shot"


async def test_sft_mode_uses_request_voice_and_needs_no_prompt(tmp_path):
    server = FakeServer(_pcm(0.5, rate=22050))
    plugin = await _plugin(server, tmp_path, mode="sft", spk_id="中文女", prompt_wav="", sample_rate="22050")

    chunks = await _synthesize(plugin, "hello", request_config=TTSRequestConfig(voice="英文男"))

    request = server.requests[0]
    assert request.url.path == "/inference_sft"
    form = parse_qs(_form(request).decode())
    assert form == {"tts_text": ["hello"], "spk_id": ["英文男"]}
    assert chunks[-1].is_final


async def test_missing_prompt_wav_skips_sentences_without_crashing(tmp_path):
    server = FakeServer(_pcm(0.5))
    plugin = await _plugin(server, tmp_path, prompt_wav=str(tmp_path / "missing.wav"))

    assert await _synthesize(plugin, "hello") == []
    assert server.requests == []


async def test_server_error_skips_only_that_sentence(tmp_path):
    server = FakeServer(_pcm(0.5), status=500)
    plugin = await _plugin(server, tmp_path)

    assert await _synthesize(plugin, "one", "two") == []
    assert len(server.requests) == 2


async def test_unknown_mode_is_rejected():
    plugin = CosyVoiceLocalTTSPlugin()
    with pytest.raises(ValueError, match="mode"):
        await plugin.initialize(PluginConfig(plugin_name="tts.cosyvoice_local", params={"mode": "clone"}))


async def test_shutdown_closes_client(tmp_path):
    plugin = await _plugin(FakeServer(b""), tmp_path)
    client = plugin.client

    await plugin.shutdown()

    assert client.is_closed and plugin.client is None
