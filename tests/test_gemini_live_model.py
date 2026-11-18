"""The default Gemini Live model must be a currently supported model ID."""

from pathlib import Path

from inference.plugins.voice_llm.gemini_live import GeminiLivePlugin

RETIRED_MODEL = "gemini-3.1-flash-live-preview"
REPLACEMENT_MODEL = "gemini-3.8-live"


def test_default_model_is_supported():
    plugin = GeminiLivePlugin()
    assert plugin.model != RETIRED_MODEL
    assert plugin.model == REPLACEMENT_MODEL


def test_bundled_config_uses_supported_model():
    config = (
        Path(__file__).resolve().parents[1]
        / "infra"
        / "config"
        / "omni_models"
        / "gemini.yaml"
    )
    text = config.read_text(encoding="utf-8")
    assert RETIRED_MODEL not in text
    assert REPLACEMENT_MODEL in text
