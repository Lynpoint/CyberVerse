import asyncio
from contextlib import suppress
import json
import logging
import ssl
from typing import Any, AsyncIterator

from inference.core.types import ASRRequestConfig, PluginConfig, TranscriptEvent
from inference.plugins.asr.base import ASRPlugin

logger = logging.getLogger(__name__)


def _parse_chunk_size(value: Any) -> list[int]:
    if isinstance(value, str):
        value = [part for part in value.replace(" ", "").split(",") if part]
    return [int(part) for part in value]


def _parse_bool(value: Any) -> bool:
    if isinstance(value, str):
        return value.strip().lower() not in ("false", "0", "no", "off", "")
    return bool(value)


class FunASRPlugin(ASRPlugin):
    """Streaming ASR through a FunASR runtime WebSocket server.

    Speaks the FunASR runtime protocol (runtime/docs/websocket_protocol.md):
    a JSON config message, raw PCM16 audio frames, then {"is_speaking": false}.
    In 2pass mode the server streams "2pass-online" text deltas while the user
    speaks and a punctuated "2pass-offline" result at each sentence end.
    """

    name = "asr.funasr"

    def __init__(self) -> None:
        self.ws_url = "ws://127.0.0.1:10095"
        self.mode = "2pass"
        self.chunk_size = [5, 10, 5]
        self.chunk_interval = 10
        self.sample_rate = 16000
        self.language = "zh"
        self.itn = True
        self.hotwords = ""
        self.ssl_verify = True
        self.final_timeout_seconds = 3.0

    async def initialize(self, config: PluginConfig) -> None:
        params = config.params
        self.ws_url = params.get("ws_url") or self.ws_url
        self.mode = params.get("mode", self.mode)
        self.chunk_size = _parse_chunk_size(params.get("chunk_size", self.chunk_size))
        self.chunk_interval = int(params.get("chunk_interval", self.chunk_interval))
        self.sample_rate = int(params.get("sample_rate", self.sample_rate))
        self.language = params.get("language", self.language)
        self.itn = _parse_bool(params.get("itn", self.itn))
        hotwords = params.get("hotwords", self.hotwords)
        # The server expects hotwords as a JSON string such as {"word": 20}.
        self.hotwords = (
            json.dumps(hotwords, ensure_ascii=False)
            if isinstance(hotwords, dict)
            else str(hotwords or "")
        )
        self.ssl_verify = _parse_bool(params.get("ssl_verify", self.ssl_verify))
        self.final_timeout_seconds = float(
            params.get("final_timeout_seconds", self.final_timeout_seconds)
        )

    async def transcribe_stream(
        self,
        audio_stream: AsyncIterator[bytes],
        request_config: ASRRequestConfig | None = None,
    ) -> AsyncIterator[TranscriptEvent]:
        import websockets

        language = (request_config.language if request_config else "") or self.language
        if language == "auto":
            language = ""
        session_id = (request_config.session_id if request_config else "") or "cyberverse"

        try:
            ws = await self._connect(websockets)
        except OSError as exc:
            raise RuntimeError(f"FunASR server unreachable at {self.ws_url}: {exc}") from exc

        sender_task = asyncio.create_task(self._send_audio(ws, audio_stream, session_id))
        recv_task: asyncio.Task | None = None
        partial = ""
        try:
            while True:
                if recv_task is None:
                    recv_task = asyncio.create_task(ws.recv())
                waiting: set[asyncio.Task] = {recv_task}
                if not sender_task.done():
                    waiting.add(sender_task)
                # Once all audio is sent, wait only a bounded time for the last result.
                timeout = self.final_timeout_seconds if sender_task.done() else None
                done, _ = await asyncio.wait(
                    waiting, timeout=timeout, return_when=asyncio.FIRST_COMPLETED
                )
                if not done:
                    break
                if sender_task in done:
                    try:
                        await sender_task
                    except websockets.exceptions.ConnectionClosed as exc:
                        raise RuntimeError(
                            f"FunASR WebSocket closed while sending audio: {exc}"
                        ) from exc
                    if recv_task not in done:
                        continue

                try:
                    message = recv_task.result()
                except websockets.exceptions.ConnectionClosed as exc:
                    if sender_task.done():
                        break
                    raise RuntimeError(f"FunASR WebSocket closed unexpectedly: {exc}") from exc
                recv_task = None

                result = self._parse_message(message)
                if result is None:
                    continue
                mode, text, server_final = result
                if mode.endswith("offline"):
                    partial = ""
                    if text:
                        yield TranscriptEvent(text=text, is_final=True, language=language)
                elif text:
                    # Online results are deltas; send the utterance so far.
                    partial += text
                    yield TranscriptEvent(text=partial, is_final=False, language=language)
                # After the end flag the server marks its last result is_final.
                if server_final and sender_task.done():
                    break
        finally:
            for task in (sender_task, recv_task):
                if task is not None and not task.done():
                    task.cancel()
                    with suppress(asyncio.CancelledError):
                        await task
            await ws.close()

        # The online-only mode never sends an offline result; keep its last text.
        if partial:
            yield TranscriptEvent(text=partial, is_final=True, language=language)

    async def _send_audio(
        self,
        ws: Any,
        audio_stream: AsyncIterator[bytes],
        session_id: str,
    ) -> None:
        await ws.send(json.dumps(self._start_message(session_id), ensure_ascii=False))
        async for chunk in audio_stream:
            if chunk:
                await ws.send(chunk)
        await ws.send(json.dumps({"is_speaking": False}))

    def _start_message(self, session_id: str) -> dict[str, Any]:
        message: dict[str, Any] = {
            "mode": self.mode,
            "chunk_size": self.chunk_size,
            "chunk_interval": self.chunk_interval,
            "wav_name": session_id,
            "wav_format": "pcm",
            "audio_fs": self.sample_rate,
            "is_speaking": True,
            "itn": self.itn,
        }
        if self.hotwords:
            message["hotwords"] = self.hotwords
        return message

    @staticmethod
    def _parse_message(message: Any) -> tuple[str, str, bool] | None:
        if isinstance(message, bytes):
            message = message.decode("utf-8", errors="replace")
        try:
            event = json.loads(message)
        except (TypeError, ValueError):
            logger.warning("Ignoring non-JSON FunASR message: %r", message)
            return None
        if not isinstance(event, dict):
            return None
        mode = str(event.get("mode", "")).lower()
        text = event.get("text", "")
        text = text.strip() if isinstance(text, str) else ""
        return mode, text, event.get("is_final") is True

    async def _connect(self, websockets: Any):
        kwargs: dict[str, Any] = {"max_size": None}
        if self.ws_url.startswith("wss://") and not self.ssl_verify:
            # The FunASR docker image serves wss with a self-signed certificate by default.
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
            kwargs["ssl"] = context
        return await websockets.connect(self.ws_url, **kwargs)

    async def shutdown(self) -> None:
        return None
