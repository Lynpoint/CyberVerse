import os
import re
from pathlib import Path

import yaml

_ENV_VAR_PATTERN = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")
_MODEL_CONFIG_GLOBS = ("*.yaml", "*.yml")
_CONVENTIONAL_MODEL_CONFIG_DIRS = {
    "omni": "omni_models",
    "llm": "llm_models",
    "embedding": "embedding_models",
    "tts": "tts_models",
    "asr": "asr_models",
}
_DEFAULT_CONFIG_PATH = Path("config/cyberverse.yaml")
_LEGACY_CONFIG_PATH = Path("cyberverse_config.yaml")


def _replace_env_in_value(value):
    """Substitute ${VAR} placeholders inside an already-parsed value.

    Substitution happens after YAML parsing so an environment value is treated
    as data, never as YAML source. A value containing ':', '#', quotes or a
    newline therefore cannot corrupt the document or change its structure.
    """
    def _replace(match: re.Match) -> str:
        return os.environ.get(match.group(1), match.group(0))

    if isinstance(value, str):
        substituted = _ENV_VAR_PATTERN.sub(_replace, value)
        # Text-level substitution used to feed the whole value back through
        # yaml.safe_load, so an env value like "8080" or "true" became a number
        # or bool. Keep that behavior for values that are a single placeholder,
        # without letting YAML syntax in arbitrary values corrupt the document.
        if _ENV_VAR_PATTERN.fullmatch(value):
            try:
                parsed = yaml.safe_load(substituted)
            except yaml.YAMLError:
                return substituted
            if isinstance(parsed, (int, float, bool)) or parsed is None:
                return parsed
        return substituted
    if isinstance(value, list):
        return [_replace_env_in_value(item) for item in value]
    if isinstance(value, dict):
        return {
            _replace_env_in_value(key): _replace_env_in_value(item)
            for key, item in value.items()
        }
    return value


def _load_yaml_file(config_path: Path) -> dict:
    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_path, encoding="utf-8") as f:
        raw = f.read()

    data = yaml.safe_load(raw)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"Config root must be a mapping: {config_path}")
    return _replace_env_in_value(data)


def load_dotenv(path: str | Path) -> None:
    """Load KEY=VALUE pairs from a dotenv file into the process environment."""
    env_path = Path(path)
    if not env_path.exists():
        return
    if not env_path.is_file():
        raise FileNotFoundError(f"Dotenv path is not a file: {env_path}")

    with open(env_path, encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            key, sep, value = line.partition("=")
            if not sep:
                continue
            key = key.strip()
            value = value.strip()
            if not key:
                continue
            if len(value) >= 2 and (
                (value[0] == '"' and value[-1] == '"')
                or (value[0] == "'" and value[-1] == "'")
            ):
                value = value[1:-1]
            os.environ[key] = value


def resolve_config_path(config_path: str | Path) -> Path:
    """Resolve the config path, falling back from the new default to the legacy file."""
    path = Path(config_path)
    if path.exists():
        return path
    if path == _DEFAULT_CONFIG_PATH and _LEGACY_CONFIG_PATH.exists():
        return _LEGACY_CONFIG_PATH
    return path


def _dotenv_paths(config_path: Path) -> list[Path]:
    config_dir = config_path.parent
    paths: list[Path] = []
    if config_dir.name == "config":
        paths.append(config_dir.parent / ".env")
    paths.extend([config_dir / ".env", config_dir / "env"])
    return paths


def _model_config_files(model_config_dir: Path) -> list[Path]:
    files: list[Path] = []
    for pattern in _MODEL_CONFIG_GLOBS:
        files.extend(model_config_dir.glob(pattern))
    return sorted({path.resolve(): path for path in files}.values(), key=lambda p: p.name)


def _single_model_config(model_file: Path, category: str) -> tuple[str, dict]:
    model_data = _load_yaml_file(model_file)
    if len(model_data) != 1:
        raise ValueError(
            f"{category} model config file must contain exactly one top-level model: "
            f"{model_file}"
        )
    model_name, model_config = next(iter(model_data.items()))
    if not isinstance(model_name, str) or not model_name.strip():
        raise ValueError(f"{category} model name must be a non-empty string: {model_file}")
    if not isinstance(model_config, dict):
        raise ValueError(f"{category} model config value must be a mapping: {model_file}")
    return model_name, model_config


def _merge_model_config_dir(
    model_config_dir: Path,
    category: str,
    *,
    require_dir: bool,
) -> dict[str, dict]:
    if not model_config_dir.exists():
        if require_dir:
            raise FileNotFoundError(
                f"{category} model config dir not found: {model_config_dir}"
            )
        return {}
    if not model_config_dir.is_dir():
        raise NotADirectoryError(
            f"{category} model config dir is not a directory: {model_config_dir}"
        )

    merged: dict[str, dict] = {}
    seen: set[str] = set()
    for model_file in _model_config_files(model_config_dir):
        model_name, model_config = _single_model_config(model_file, category)
        if model_name in seen:
            raise ValueError(f"Duplicate {category} model config for {model_name!r}")
        seen.add(model_name)
        merged[model_name] = model_config
    return merged


def _merge_avatar_model_configs(config: dict, config_path: Path) -> dict:
    inference = config.get("inference")
    if not isinstance(inference, dict):
        return config
    avatar = inference.get("avatar")
    if not isinstance(avatar, dict):
        return config

    raw_model_config_dir = avatar.get("model_config_dir")
    if raw_model_config_dir is None or str(raw_model_config_dir).strip() == "":
        return config

    model_config_dir = Path(str(raw_model_config_dir)).expanduser()
    if not model_config_dir.is_absolute():
        model_config_dir = config_path.parent / model_config_dir

    external_models = _merge_model_config_dir(
        model_config_dir,
        "avatar",
        require_dir=True,
    )
    for model_name, model_config in external_models.items():
        # Inline model configs in the main CyberVerse config are treated as local
        # overrides and remain the write target for that model.
        if model_name not in avatar:
            avatar[model_name] = model_config

    return config


def _repo_root_for_config(config_path: Path) -> Path:
    config_dir = config_path.resolve().parent
    if config_dir.name == "config" and config_dir.parent.name == "infra":
        return config_dir.parent.parent
    if config_dir.name == "config":
        return config_dir.parent
    return config_dir


def _conventional_model_config_dirs(config_path: Path, dir_name: str) -> list[Path]:
    repo_root = _repo_root_for_config(config_path)
    candidates = [
        repo_root / "infra" / "config" / dir_name,
        repo_root / "config" / dir_name,
        config_path.resolve().parent / dir_name,
    ]
    unique: list[Path] = []
    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        unique.append(candidate)
    return unique


def _merge_conventional_model_configs(config: dict, config_path: Path) -> dict:
    inference = config.setdefault("inference", {})
    if not isinstance(inference, dict):
        return config

    for category, dir_name in _CONVENTIONAL_MODEL_CONFIG_DIRS.items():
        section = inference.setdefault(category, {})
        if not isinstance(section, dict):
            continue

        preserved = {k: v for k, v in section.items() if not isinstance(v, dict)}
        inline_models = {k: v for k, v in section.items() if isinstance(v, dict)}
        merged_models: dict[str, dict] = {}

        for model_config_dir in _conventional_model_config_dirs(config_path, dir_name):
            merged_models.update(
                _merge_model_config_dir(
                    model_config_dir,
                    category,
                    require_dir=False,
                )
            )

        section.clear()
        section.update(preserved)
        section.update(merged_models)
        section.update(inline_models)

    return config


def load_config(config_path: str | Path) -> dict:
    """Load YAML config with env substitution and external model files.

    Only substitutes explicit ${VAR_NAME} patterns, not arbitrary env vars.
    Unmatched patterns are left as-is.
    """
    config_path = resolve_config_path(config_path)
    for dotenv_path in _dotenv_paths(config_path):
        load_dotenv(dotenv_path)
    os.environ["CYBERVERSE_CONFIG_DIR"] = str(config_path.parent.resolve())
    config = _load_yaml_file(config_path)

    config = _merge_avatar_model_configs(config, config_path)
    return _merge_conventional_model_configs(config, config_path)
