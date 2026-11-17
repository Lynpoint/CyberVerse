"""Tests for the FunASR runtime WebSocket ASR plugin."""
import asyncio
import json
import ssl
import sys
from types import ModuleType, SimpleNamespace

import pytest

from inference.core.types import ASRRequestConfig, PluginConfig
from inference.plugins.asr.funasr_plugin import FunASRPlugin


class FakeConnectionClosed(Exception):
    pass


class FakeWebSocket:
    """Replays scripted server messages; a message is released once the
    client has sent the given number of audio frames (or the end flag)."""

    def __init__(self, script: list[tuple[int | str, dict]]) -> None:
        self.script = list(script)
        self.sent_json: list[dict] = []
        self.sent_audio: list[bytes] = []
        self.closed = False
        self.ended = False
        self._ready: asyncio.Queue[str] = asyncio.Queue()
        self._close_after_script = False

    async def send(self, payload) -> None:
        if isinstance(payload, bytes):
            self.sent_audio.append(payload)
        else:
            event = json.loads(payload)
            self.sent_json.append(event)
            if event.get("is_speaking") is False:
                self.ended = True
        await self._release()

    async def _release(self) -> None:
        while self.script:
            trigger, message = self.script[0]
            due = self.ended if trigger == "end" else len(self.sent_audio) >= trigger
            if not due:
                return
            self.script.pop(0)
            await self._ready.put(json.dumps(message, ensure_ascii=False))

    async def recv(self) -> str:
        if self._close_after_script and self._ready.empty() and not self.script:
            raise FakeConnectionClosed("closed")
        return await self._ready.get()

    async def close(self) -> None:
        self.closed = True


@pytest.fixture
def fake_websockets(monkeypatch):
    module = ModuleType("websockets")
    module.exceptions = SimpleNamespace(ConnectionClosed=FakeConnectionClosed)
    module.connect_calls = []
    module.socket = None

    async def connect(url, **kwargs):
        module.connect_calls.append((url, kwargs))
        return module.socket

    module.connect = connect
    monkeypatch.setitem(sys.modules, "websockets", module)
    return module


async def _audio(*chunks: bytes):
    for chunk in chunks:
        yield chunk
        await asyncio.sleep(0)


async def _collect(plugin, stream, request_config=None):
    return [event async for event in plugin.transcribe_stream(stream, request_config)]


async def _plugin(**params) -> FunASRPlugin:
    plugin = FunASRPlugin()
    await plugin.initialize(PluginConfig(plugin_name="asr.funasr", params=params))
    return plugin


async def test_initialize_reads_yaml_style_strings():
    plugin = await _plugin(
        ws_url="wss://asr.local:10095",
        chunk_size="8, 8, 4",
        sample_rate="8000",
        itn="false",
        ssl_verify="false",
        hotwords={"CyberVerse": 20},
    )
    assert plugin.ws_url == "wss://asr.local:10095"
    assert plugin.chunk_size == [8, 8, 4]
    assert plugin.sample_rate == 8000
    assert plugin.itn is False
    assert plugin.ssl_verify is False
    assert json.loads(plugin.hotwords) == {"CyberVerse": 20}


async def test_2pass_streams_partials_then_punctuated_final(fake_websockets):
    fake_websockets.socket = FakeWebSocket([
        (1, {"mode": "2pass-online", "text": "今天"}),
        (2, {"mode": "2pass-online", "text": "天气"}),
        ("end", {"mode": "2pass-offline", "text": "今天天气。", "is_final": True}),
    ])
    plugin = await _plugin(language="zh")

    events = await _collect(
        plugin, _audio(b"\x01\x00" * 4, b"\x02\x00" * 4),
        ASRRequestConfig(session_id="s1"),
    )

    assert [(e.text, e.is_final) for e in events] == [
        ("今天", False),
        ("今天天气", False),
        ("今天天气。", True),
    ]
    assert all(e.language == "zh" for e in events)
    ws = fake_websockets.socket
    start = ws.sent_json[0]
    assert start["mode"] == "2pass" and start["wav_format"] == "pcm"
    assert start["wav_name"] == "s1" and start["audio_fs"] == 16000
    assert start["chunk_size"] == [5, 10, 5] and start["is_speaking"] is True
    assert "hotwords" not in start
    assert ws.sent_audio == [b"\x01\x00" * 4, b"\x02\x00" * 4]
    assert ws.sent_json[-1] == {"is_speaking": False}
    assert ws.closed


async def test_partial_resets_after_each_sentence(fake_websockets):
    fake_websockets.socket = FakeWebSocket([
        (1, {"mode": "2pass-online", "text": "你好"}),
        (1, {"mode": "2pass-offline", "text": "你好。"}),
        (2, {"mode": "2pass-online", "text": "再见"}),
        ("end", {"mode": "2pass-offline", "text": "再见。", "is_final": True}),
    ])
    plugin = await _plugin()

    events = await _collect(plugin, _audio(b"a", b"b"))

    assert [(e.text, e.is_final) for e in events] == [
        ("你好", False), ("你好。", True), ("再见", False), ("再见。", True),
    ]


async def test_online_mode_finalizes_last_partial_when_server_stays_silent(fake_websockets):
    fake_websockets.socket = FakeWebSocket([
        (1, {"mode": "online", "text": "hello"}),
    ])
    plugin = await _plugin(mode="online", final_timeout_seconds="0.05", language="auto")

    events = await _collect(plugin, _audio(b"a"))

    assert [(e.text, e.is_final, e.language) for e in events] == [
        ("hello", False, ""), ("hello", True, ""),
    ]


async def test_server_closing_after_audio_ends_is_not_an_error(fake_websockets):
    ws = FakeWebSocket([("end", {"mode": "2pass-offline", "text": "end"})])
    ws._close_after_script = True
    fake_websockets.socket = ws
    plugin = await _plugin()

    events = await _collect(plugin, _audio(b"a"))

    assert [(e.text, e.is_final) for e in events] == [("end", True)]


async def test_server_closing_mid_stream_raises_runtime_error(fake_websockets):
    ws = FakeWebSocket([])
    ws._close_after_script = True
    fake_websockets.socket = ws
    plugin = await _plugin()

    async def endless():
        while True:
            yield b"a"
            await asyncio.sleep(0.01)

    with pytest.raises(RuntimeError, match="closed unexpectedly"):
        await _collect(plugin, endless())


async def test_unreachable_server_raises_runtime_error(fake_websockets):
    async def refuse(url, **kwargs):
        raise ConnectionRefusedError("refused")

    fake_websockets.connect = refuse
    plugin = await _plugin()

    with pytest.raises(RuntimeError, match="unreachable"):
        await _collect(plugin, _audio(b"a"))


async def test_hotwords_and_self_signed_wss(fake_websockets):
    fake_websockets.socket = FakeWebSocket([("end", {"mode": "2pass-offline", "text": "ok", "is_final": True})])
    plugin = await _plugin(
        ws_url="wss://127.0.0.1:10095", ssl_verify=False, hotwords='{"阿里巴巴": 20}',
    )

    await _collect(plugin, _audio(b"a"))

    url, kwargs = fake_websockets.connect_calls[0]
    assert url == "wss://127.0.0.1:10095"
    assert kwargs["ssl"].verify_mode == ssl.CERT_NONE
    assert fake_websockets.socket.sent_json[0]["hotwords"] == '{"阿里巴巴": 20}'


async def test_plain_ws_does_not_pass_ssl(fake_websockets):
    fake_websockets.socket = FakeWebSocket([("end", {"mode": "2pass-offline", "text": "ok", "is_final": True})])
    plugin = await _plugin(ssl_verify=False)

    await _collect(plugin, _audio(b"a"))

    assert "ssl" not in fake_websockets.connect_calls[0][1]
