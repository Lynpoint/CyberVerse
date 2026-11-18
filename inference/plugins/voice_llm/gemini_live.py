import asyncio
import base64
import json
import logging
import time
from dataclasses import dataclass
from typing import Any, AsyncIterator
from urllib.parse import urlencode

from inference.core.types import (
    AudioChunk,
    PluginConfig,
    VoiceLLMInputEvent,
    VoiceLLMOutputEvent,
    VoiceLLMSessionConfig,
)
from inference.plugins.voice_llm.base import VoiceCheckError, VoiceLLMPlugin

logger = logging.getLogger(__name__)


class GeminiLivePlugin(VoiceLLMPlugin):
    """Google Gemini Live API plugin using the raw WebSocket protocol."""

    name = "omni.gemini"

    def __init__(self) -> None:
        self.api_key = ""
        self.model = "gemini-3.8-live"
        self.ws_url = (
            "wss://generativelanguage.googleapis.com/ws/"
            "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
        )
        self.voice = "Kore"
        self.system_prompt = ""
        self.input_sample_rate = 16000
        self.output_sample_rate = 24000
        self.response_modalities = ["AUDIO"]
        self.proxy: str | None = None
        self.websocket_compression: str | None = None
        self.max_message_size = 10_000_000
        self.connect_attempts = 1
        self.connect_retry_delay_seconds = 1.0
        self.input_transcription = True
        self.output_transcription = True
        self.thinking_level = ""
        self._active_ws: Any | None = None

    async def initialize(self, config: PluginConfig) -> None:
        params = config.params
        self.api_key = str(params.get("api_key") or self.api_key)
        self.model = str(params.get("model") or self.model)
        self.ws_url = str(params.get("ws_url") or self.ws_url)
        self.voice = str(params.get("voice") or self.voice)
        self.system_prompt = str(params.get("system_prompt") or self.system_prompt)
        self.input_sample_rate = int(params.get("input_sample_rate", self.input_sample_rate))
        self.output_sample_rate = int(params.get("output_sample_rate", self.output_sample_rate))
        self.response_modalities = self._string_list(
            params.get("response_modalities"),
            self.response_modalities,
        )
        self.proxy = self._optional_str(params.get("proxy"), self.proxy)
        self.websocket_compression = self._optional_str(
            params.get("websocket_compression"),
            self.websocket_compression,
        )
        self.max_message_size = int(params.get("max_message_size", self.max_message_size))
        self.connect_attempts = max(1, int(params.get("connect_attempts", self.connect_attempts)))
        self.connect_retry_delay_seconds = float(
            params.get("connect_retry_delay_seconds", self.connect_retry_delay_seconds)
        )
        self.input_transcription = self._bool(params.get("input_transcription"), self.input_transcription)
        self.output_transcription = self._bool(params.get("output_transcription"), self.output_transcription)
        self.thinking_level = str(params.get("thinking_level") or self.thinking_level)
        if not self.api_key:
            raise RuntimeError("gemini api_key is required")
        if not self.model:
            raise RuntimeError("gemini model is required")
        if not self.ws_url:
            raise RuntimeError("gemini ws_url is required")

    async def check_voice(
        self,
        session_config: VoiceLLMSessionConfig | None = None,
    ) -> None:
        import websockets

        ws = await self._connect(websockets)
        try:
            await self._configure_session(ws, session_config or VoiceLLMSessionConfig())
        except RuntimeError as exc:
            raise VoiceCheckError(str(exc)) from exc
        finally:
            await ws.close()

    async def converse_stream(
        self,
        input_stream: AsyncIterator[VoiceLLMInputEvent],
        session_config: VoiceLLMSessionConfig | None = None,
    ) -> AsyncIterator[VoiceLLMOutputEvent]:
        import websockets

        config = session_config or VoiceLLMSessionConfig()
        ws = await self._connect(websockets)
        self._active_ws = ws
        output_queue: asyncio.Queue[VoiceLLMOutputEvent | Exception | None] = asyncio.Queue()
        response_done = asyncio.Event()
        sender_task: asyncio.Task | None = None
        receiver_task: asyncio.Task | None = None
        try:
            await self._configure_session(ws, config)
            sender_task = asyncio.create_task(self._send_inputs(ws, input_stream, output_queue, response_done))
            receiver_task = asyncio.create_task(self._receive_events(ws, config.session_id, output_queue, response_done))
            while True:
                item = await output_queue.get()
                if item is None:
                    break
                if isinstance(item, Exception):
                    raise item
                yield item
        finally:
            for task in (sender_task, receiver_task):
                if task and not task.done():
                    task.cancel()
                    try:
                        await task
                    except asyncio.CancelledError:
                        pass
            if self._active_ws is ws:
                self._active_ws = None
            await ws.close()

    async def interrupt(self) -> None:
        ws = self._active_ws
        if ws is None:
            return
        try:
            await ws.close()
        except Exception:
            logger.debug("Failed to close gemini live websocket during interrupt", exc_info=True)

    async def _connect(self, websockets: Any):
        url = self._connection_url()
        kwargs: dict[str, Any] = {
            "compression": self.websocket_compression,
            "max_size": self.max_message_size,
        }
        if self.proxy is not None:
            kwargs["proxy"] = self.proxy
        last_error: Exception | None = None
        for attempt in range(1, self.connect_attempts + 1):
            try:
                return await websockets.connect(url, **kwargs)
            except Exception as exc:
                last_error = exc
                if attempt >= self.connect_attempts:
                    break
                logger.warning(
                    "gemini live connect attempt %d/%d failed: %s",
                    attempt,
                    self.connect_attempts,
                    exc,
                )
                await asyncio.sleep(self.connect_retry_delay_seconds)
        assert last_error is not None
        raise last_error

    def _connection_url(self) -> str:
        separator = "&" if "?" in self.ws_url else "?"
        return f"{self.ws_url}{separator}{urlencode({'key': self.api_key})}"

    async def _configure_session(
        self,
        ws: Any,
        session_config: VoiceLLMSessionConfig,
    ) -> None:
        await self._send_json(ws, {"setup": self._setup_payload(session_config)})
        while True:
            event = self._decode_message(await ws.recv())
            self._log_server_event(session_config.session_id, event)
            if "setupComplete" in event:
                return
            if "error" in event:
                raise RuntimeError(self._error_message(event))

    async def _send_inputs(
        self,
        ws: Any,
        input_stream: AsyncIterator[VoiceLLMInputEvent],
        output_queue: asyncio.Queue[VoiceLLMOutputEvent | Exception | None],
        response_done: asyncio.Event,
    ) -> None:
        expects_response = False
        try:
            async for event in input_stream:
                if event.text:
                    expects_response = True
                    response_done.clear()
                    await self._send_text(ws, event.text)
                    continue
                if event.audio:
                    await self._send_audio(ws, event.audio)
            if expects_response:
                await asyncio.wait_for(response_done.wait(), timeout=60.0)
        except Exception as exc:
            await output_queue.put(exc)
        finally:
            try:
                await ws.close()
            except Exception:
                pass

    async def _send_text(self, ws: Any, text: str) -> None:
        await self._send_json(
            ws,
            {
                "clientContent": {
                    "turns": [{"role": "user", "parts": [{"text": text}]}],
                    "turnComplete": True,
                }
            },
        )

    async def _send_audio(self, ws: Any, audio: bytes) -> None:
        await self._send_json(
            ws,
            {
                "realtimeInput": {
                    "audio": {
                        "data": base64.b64encode(audio).decode("ascii"),
                        "mimeType": f"audio/pcm;rate={self.input_sample_rate}",
                    }
                }
            },
        )

    async def _receive_events(
        self,
        ws: Any,
        session_id: str,
        output_queue: asyncio.Queue[VoiceLLMOutputEvent | Exception | None],
        response_done: asyncio.Event,
    ) -> None:
        turn_state = _GeminiTurnState(session_id=session_id or "gemini")
        try:
            async for message in ws:
                event = self._decode_message(message)
                self._log_server_event(session_id, event)
                if "error" in event:
                    raise RuntimeError(self._error_message(event))

                server_content = event.get("serverContent")
                if not isinstance(server_content, dict):
                    continue

                if server_content.get("interrupted"):
                    turn_state.ensure_turn()
                    await output_queue.put(
                        VoiceLLMOutputEvent(
                            barge_in=True,
                            question_id=turn_state.question_id,
                            reply_id=turn_state.reply_id,
                        )
                    )

                input_transcription = server_content.get("inputTranscription")
                if isinstance(input_transcription, dict):
                    text = str(input_transcription.get("text") or "")
                    if text:
                        turn_state.ensure_turn()
                        await output_queue.put(
                            VoiceLLMOutputEvent(
                                user_transcript=text,
                                question_id=turn_state.question_id,
                                reply_id=turn_state.reply_id,
                            )
                        )

                output_transcription = server_content.get("outputTranscription")
                if isinstance(output_transcription, dict):
                    text = str(output_transcription.get("text") or "")
                    if text:
                        turn_state.ensure_turn()
                        turn_state.assistant_text += text
                        await output_queue.put(
                            VoiceLLMOutputEvent(
                                transcript=text,
                                question_id=turn_state.question_id,
                                reply_id=turn_state.reply_id,
                            )
                        )

                model_turn = server_content.get("modelTurn")
                if isinstance(model_turn, dict):
                    parts = model_turn.get("parts")
                    if isinstance(parts, list):
                        for part in parts:
                            if not isinstance(part, dict):
                                continue
                            if isinstance(part.get("text"), str) and part["text"]:
                                turn_state.ensure_turn()
                                turn_state.assistant_text += part["text"]
                                await output_queue.put(
                                    VoiceLLMOutputEvent(
                                        transcript=part["text"],
                                        question_id=turn_state.question_id,
                                        reply_id=turn_state.reply_id,
                                    )
                                )
                            inline_data = part.get("inlineData")
                            if not isinstance(inline_data, dict):
                                continue
                            payload = str(inline_data.get("data") or "")
                            if not payload:
                                continue
                            audio_payload = base64.b64decode(payload)
                            if not audio_payload:
                                continue
                            turn_state.ensure_turn()
                            turn_state.has_audio = True
                            await output_queue.put(
                                VoiceLLMOutputEvent(
                                    audio=AudioChunk(
                                        data=audio_payload,
                                        sample_rate=self.output_sample_rate,
                                        channels=1,
                                        format="pcm_s16le",
                                    ),
                                    question_id=turn_state.question_id,
                                    reply_id=turn_state.reply_id,
                                )
                            )

                if server_content.get("turnComplete"):
                    if turn_state.has_content:
                        await output_queue.put(
                            VoiceLLMOutputEvent(
                                audio=AudioChunk(
                                    data=b"",
                                    sample_rate=self.output_sample_rate,
                                    channels=1,
                                    format="pcm_s16le",
                                    is_final=True,
                                )
                                if turn_state.has_audio
                                else None,
                                transcript=turn_state.assistant_text,
                                is_final=True,
                                question_id=turn_state.question_id,
                                reply_id=turn_state.reply_id,
                            )
                        )
                    turn_state.reset()
                    response_done.set()
        except Exception as exc:
            if not getattr(ws, "closed", False):
                await output_queue.put(exc)
        finally:
            await output_queue.put(None)

    def _setup_payload(self, session_config: VoiceLLMSessionConfig) -> dict[str, Any]:
        generation_config: dict[str, Any] = {
            "responseModalities": self.response_modalities,
            "speechConfig": {
                "voiceConfig": {
                    "prebuiltVoiceConfig": {
                        "voiceName": session_config.voice or self.voice,
                    }
                }
            },
        }
        if self.thinking_level:
            generation_config["thinkingConfig"] = {"thinkingLevel": self.thinking_level}

        payload: dict[str, Any] = {
            "model": self._model_resource_name(),
            "generationConfig": generation_config,
        }
        instructions = self._instructions(session_config)
        if instructions:
            payload["systemInstruction"] = {"parts": [{"text": instructions}]}
        if self.input_transcription:
            payload["inputAudioTranscription"] = {}
        if self.output_transcription:
            payload["outputAudioTranscription"] = {}
        return payload

    def _model_resource_name(self) -> str:
        return self.model if self.model.startswith("models/") else f"models/{self.model}"

    def _instructions(self, session_config: VoiceLLMSessionConfig) -> str:
        parts: list[str] = []
        if session_config.bot_name:
            parts.append(f"名字：{session_config.bot_name}")
        parts.append(session_config.system_prompt or self.system_prompt)
        if session_config.speaking_style:
            parts.append(f"说话风格：{session_config.speaking_style}")
        if session_config.dialog_context:
            parts.append("以下是最近的对话上下文，请在回答时保持连续性：")
            for item in session_config.dialog_context:
                role = "用户" if item.role == "user" else "助手"
                parts.append(f"{role}：{item.text}")
        return "\n".join(part for part in parts if part.strip())

    @staticmethod
    async def _send_json(ws: Any, payload: dict[str, Any]) -> None:
        await ws.send(json.dumps(payload, ensure_ascii=False))

    @staticmethod
    def _decode_message(message: str | bytes) -> dict[str, Any]:
        if isinstance(message, bytes):
            message = message.decode("utf-8")
        return json.loads(message)

    @staticmethod
    def _error_message(event: dict[str, Any]) -> str:
        error = event.get("error")
        if isinstance(error, dict):
            message = error.get("message") or error.get("status") or error.get("code")
            if message:
                return str(message)
        if isinstance(error, str):
            return error
        return f"gemini error: {event}"

    @staticmethod
    def _optional_str(value: Any, default: str | None = "") -> str | None:
        if value is None:
            return default
        text = str(value).strip()
        if not text or text.lower() == "null":
            return None
        if text.startswith("${") and text.endswith("}"):
            return None
        return text

    @staticmethod
    def _bool(value: Any, default: bool) -> bool:
        if value is None:
            return default
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return value != 0
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"1", "true", "yes", "on"}:
                return True
            if normalized in {"0", "false", "no", "off"}:
                return False
        return default

    @staticmethod
    def _string_list(value: Any, default: list[str]) -> list[str]:
        if value is None:
            return list(default)
        if isinstance(value, list):
            return [str(item) for item in value if str(item).strip()]
        text = str(value).strip()
        return [text] if text else list(default)

    @classmethod
    def _server_event_log_fields(cls, event: dict[str, Any]) -> dict[str, Any]:
        fields: dict[str, Any] = {}
        server_content = event.get("serverContent")
        if isinstance(server_content, dict):
            fields["serverContent"] = {
                key: server_content.get(key)
                for key in ("turnComplete", "generationComplete", "interrupted")
                if key in server_content
            }
            model_turn = server_content.get("modelTurn")
            if isinstance(model_turn, dict):
                parts = model_turn.get("parts")
                if isinstance(parts, list):
                    fields["modelTurnParts"] = len(parts)
                    audio_bytes = 0
                    for part in parts:
                        if isinstance(part, dict):
                            inline_data = part.get("inlineData")
                            if isinstance(inline_data, dict):
                                audio_bytes += len(str(inline_data.get("data") or ""))
                    if audio_bytes:
                        fields["audio_b64_len"] = audio_bytes
            for key in ("inputTranscription", "outputTranscription"):
                transcription = server_content.get(key)
                if isinstance(transcription, dict) and transcription.get("text"):
                    fields[key] = cls._clip_text(transcription.get("text"))
        if "setupComplete" in event:
            fields["setupComplete"] = True
        if "sessionResumptionUpdate" in event:
            fields["sessionResumptionUpdate"] = True
        if "goAway" in event:
            fields["goAway"] = event.get("goAway")
        if "usageMetadata" in event:
            fields["usageMetadata"] = True
        if "error" in event:
            fields["error"] = cls._clip_text(event.get("error"))
        return fields

    @staticmethod
    def _clip_text(value: Any, limit: int = 180) -> str:
        text = str(value or "")
        if len(text) <= limit:
            return text
        return text[:limit] + "..."

    @classmethod
    def _server_event_log_level(cls, event: dict[str, Any]) -> int:
        if "error" in event:
            return logging.ERROR
        if "setupComplete" in event:
            return logging.INFO
        server_content = event.get("serverContent")
        if isinstance(server_content, dict) and (
            server_content.get("turnComplete")
            or server_content.get("generationComplete")
            or server_content.get("interrupted")
            or server_content.get("inputTranscription")
            or server_content.get("outputTranscription")
        ):
            return logging.INFO
        return logging.DEBUG

    def _log_server_event(self, session_id: str, event: dict[str, Any]) -> None:
        level = self._server_event_log_level(event)
        if not logger.isEnabledFor(level):
            return
        logger.log(
            level,
            "gemini live event session=%s keys=%s fields=%s",
            session_id or "gemini",
            sorted(event.keys()),
            json.dumps(self._server_event_log_fields(event), ensure_ascii=False, sort_keys=True),
        )

    async def shutdown(self) -> None:
        if self._active_ws is not None:
            await self._active_ws.close()
            self._active_ws = None


@dataclass
class _GeminiTurnState:
    session_id: str
    turn_index: int = 0
    question_id: str = ""
    reply_id: str = ""
    assistant_text: str = ""
    has_audio: bool = False

    @property
    def has_content(self) -> bool:
        return self.has_audio or bool(self.assistant_text)

    def start_next_turn(self) -> None:
        self.turn_index += 1
        timestamp = int(time.time() * 1000)
        self.question_id = f"{self.session_id}_q_{self.turn_index}_{timestamp}"
        self.reply_id = f"{self.session_id}_r_{self.turn_index}_{timestamp}"
        self.assistant_text = ""
        self.has_audio = False

    def ensure_turn(self) -> None:
        if not self.question_id:
            self.start_next_turn()

    def reset(self) -> None:
        self.question_id = ""
        self.reply_id = ""
        self.assistant_text = ""
        self.has_audio = False
