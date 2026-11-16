"""Pluggable vector store backends for the character RAG engine.

The RAG engine talks to a small :class:`VectorStoreBackend` interface instead of
constructing a concrete vector store inline. Chroma remains the default local
backend; Milvus is available as an optional server/embedded backend for
deployments that already run a shared vector database.

Backends own two things the engine used to hard-code for Chroma:

* persistence location (each backend decides where/how it stores data), and
* score normalization (raw similarity scores are backend specific, so each
  backend returns a normalized ``[0, 1]`` score where higher means more
  relevant). This keeps ``min_score`` filtering meaningful regardless of the
  configured backend and metric.

Concrete backend dependencies (``langchain-chroma`` / ``langchain-milvus``) are
imported lazily so non-RAG services and the unselected backend never need to be
installed.
"""

from __future__ import annotations

import logging
import re
import shutil
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

DEFAULT_BACKEND = "chroma"


def _knowledge_dir(character_dir: str | Path) -> Path:
    return Path(character_dir).expanduser().resolve() / "knowledge"


def safe_collection_name(character_id: str) -> str:
    """Sanitize a character id into a portable collection name.

    The rules are intentionally strict (alphanumeric/underscore, 3-512 chars)
    so the same name is valid for both Chroma and Milvus collections.
    """

    clean = re.sub(r"[^A-Za-z0-9_-]+", "_", character_id or "")
    clean = clean.replace("-", "_").strip("_")
    if not clean:
        clean = "default"
    name = f"cv_{clean}"
    if len(name) < 3:
        name = (name + "___")[:3]
    return name[:512]


def _l2_similarity(distance: float) -> float:
    """Map an L2 distance (lower is closer) to a ``[0, 1]`` similarity."""

    return 1.0 / (1.0 + max(float(distance), 0.0))


def _backend_settings(settings: dict[str, Any] | None) -> tuple[str, dict[str, Any]]:
    """Resolve ``(backend_name, backend_config)`` from the ``rag`` settings.

    Accepts either a bare string::

        pipeline.rag.vector_store: milvus

    or a mapping with a ``provider`` key plus provider options::

        pipeline.rag.vector_store:
          provider: milvus
          uri: http://milvus:19530
    """

    raw = (settings or {}).get("vector_store")
    if isinstance(raw, str):
        return (raw.strip().lower() or DEFAULT_BACKEND), {}
    if isinstance(raw, dict):
        provider = str(raw.get("provider") or raw.get("backend") or DEFAULT_BACKEND).strip().lower()
        return (provider or DEFAULT_BACKEND), raw
    return DEFAULT_BACKEND, {}


class VectorStoreBackend(ABC):
    """Backend-agnostic surface used by :class:`~inference.rag.engine.RAGEngine`."""

    name: str

    @abstractmethod
    def add(self, chunks: list[Any], ids: list[str]) -> None:
        """Upsert ``chunks`` under the provided stable ``ids``."""

    @abstractmethod
    def delete_source(self, source_id: str) -> None:
        """Remove every chunk previously indexed for ``source_id``."""

    @abstractmethod
    def search(self, query: str, k: int) -> list[tuple[Any, float]]:
        """Return ``(document, normalized_score)`` pairs, highest score first."""

    @abstractmethod
    def index_exists(self) -> bool:
        """Whether any persisted data exists yet for this character."""

    @abstractmethod
    def drop(self) -> None:
        """Delete all persisted data for this character."""


class ChromaBackend(VectorStoreBackend):
    """Local, file-persisted Chroma backend (the default)."""

    name = "chroma"

    def __init__(self, *, character_id: str, character_dir: str, embedding_function: Any) -> None:
        self._collection_name = safe_collection_name(character_id)
        self._persist_dir = _knowledge_dir(character_dir) / "chroma"
        self._embedding_function = embedding_function
        self._store: Any | None = None

    def _client(self):
        if self._store is not None:
            return self._store
        from langchain_chroma import Chroma

        self._persist_dir.mkdir(parents=True, exist_ok=True)
        self._store = Chroma(
            collection_name=self._collection_name,
            embedding_function=self._embedding_function,
            persist_directory=str(self._persist_dir),
        )
        return self._store

    def add(self, chunks: list[Any], ids: list[str]) -> None:
        if chunks:
            self._client().add_documents(chunks, ids=ids)

    def delete_source(self, source_id: str) -> None:
        if not self._persist_dir.exists():
            return
        collection = getattr(self._client(), "_collection", None)
        if collection is None:
            return
        try:
            collection.delete(where={"source_id": source_id})
        except Exception:
            logger.debug("Chroma source delete failed; collection recreation may be required", exc_info=True)

    def search(self, query: str, k: int) -> list[tuple[Any, float]]:
        raw = self._client().similarity_search_with_score(query, k=k)
        return [(doc, _l2_similarity(distance)) for doc, distance in raw]

    def index_exists(self) -> bool:
        return self._persist_dir.exists()

    def drop(self) -> None:
        shutil.rmtree(self._persist_dir, ignore_errors=True)


class MilvusBackend(VectorStoreBackend):
    """Milvus backend (optional).

    Defaults to an embedded Milvus Lite database persisted alongside the
    character (no server required for local development). Point ``uri`` at a
    Milvus server or Zilliz Cloud endpoint for shared deployments::

        pipeline.rag.vector_store:
          provider: milvus
          uri: http://milvus:19530
          token: "<user>:<password>"     # or Zilliz Cloud API key

    The L2 metric is used so score normalization matches the Chroma backend.
    """

    name = "milvus"

    def __init__(
        self,
        *,
        character_id: str,
        character_dir: str,
        embedding_function: Any,
        config: dict[str, Any] | None = None,
    ) -> None:
        config = config or {}
        self._collection_name = safe_collection_name(character_id)
        self._embedding_function = embedding_function
        self._token = str(config.get("token") or "")
        uri = str(config.get("uri") or "").strip()
        self._local_db: Path | None = None
        if uri:
            self._uri = uri
        else:
            self._local_db = _knowledge_dir(character_dir) / "milvus" / f"{self._collection_name}.db"
            self._uri = str(self._local_db)
        self._store: Any | None = None

    def _connection_args(self) -> dict[str, Any]:
        args: dict[str, Any] = {"uri": self._uri}
        if self._token:
            args["token"] = self._token
        return args

    def _client(self):
        if self._store is not None:
            return self._store
        from langchain_milvus import Milvus

        if self._local_db is not None:
            self._local_db.parent.mkdir(parents=True, exist_ok=True)
        self._store = Milvus(
            embedding_function=self._embedding_function,
            collection_name=self._collection_name,
            connection_args=self._connection_args(),
            index_params={"metric_type": "L2", "index_type": "AUTOINDEX", "params": {}},
            search_params={"metric_type": "L2", "params": {}},
            auto_id=False,
            drop_old=False,
            enable_dynamic_field=True,
        )
        return self._store

    def add(self, chunks: list[Any], ids: list[str]) -> None:
        if chunks:
            self._client().add_documents(chunks, ids=ids)

    def delete_source(self, source_id: str) -> None:
        if self._local_db is not None and not self._local_db.exists():
            return
        store = self._client()
        if getattr(store, "col", None) is None:
            # The collection has not been created yet (e.g. first index against a
            # remote server), so there is nothing to delete. Attempting a delete
            # here would surface below as a benign "collection not found" failure.
            return
        # Escape backslashes before quotes: a trailing backslash would otherwise
        # escape the closing quote, and ``\r`` would be read as a control char.
        safe_source = str(source_id).replace('\\', '\\\\').replace('"', '\\"')
        # ``langchain-milvus`` swallows ``MilvusException`` internally and returns
        # ``False`` instead of raising, so a failed deletion on an existing
        # collection would otherwise silently leave stale chunks behind.
        result = store.delete(expr=f'source_id == "{safe_source}"')
        if result is False:
            raise RuntimeError(f"Milvus deletion failed for source_id={source_id!r}")

    def search(self, query: str, k: int) -> list[tuple[Any, float]]:
        raw = self._client().similarity_search_with_score(query, k=k)
        return [(doc, _l2_similarity(distance)) for doc, distance in raw]

    def index_exists(self) -> bool:
        if self._local_db is not None:
            return self._local_db.exists()
        return self._client().col is not None

    def drop(self) -> None:
        if self._local_db is not None:
            shutil.rmtree(self._local_db.parent, ignore_errors=True)
            return
        try:
            self._client().col.drop()
        except Exception:
            logger.debug("Milvus collection drop failed", exc_info=True)


_BACKENDS = {"chroma": ChromaBackend, "milvus": MilvusBackend}


def create_vector_store_backend(
    settings: dict[str, Any] | None,
    *,
    character_id: str,
    character_dir: str,
    embedding_function: Any,
) -> VectorStoreBackend:
    """Instantiate the configured backend for a single character index."""

    name, config = _backend_settings(settings)
    if name not in _BACKENDS:
        raise ValueError(
            f"unknown RAG vector store backend '{name}'; expected one of {sorted(_BACKENDS)}"
        )
    if name == "milvus":
        return MilvusBackend(
            character_id=character_id,
            character_dir=character_dir,
            embedding_function=embedding_function,
            config=config,
        )
    return ChromaBackend(
        character_id=character_id,
        character_dir=character_dir,
        embedding_function=embedding_function,
    )
