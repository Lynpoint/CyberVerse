import pytest

from inference.rag.engine import HashEmbeddings, RAGEngine
from inference.rag.vector_store import (
    ChromaBackend,
    MilvusBackend,
    _l2_similarity,
    create_vector_store_backend,
    safe_collection_name,
)


def _remote_milvus(tmp_path, character_id="hero-42"):
    return create_vector_store_backend(
        {"vector_store": {"provider": "milvus", "uri": "http://milvus:19530"}},
        character_id=character_id,
        character_dir=str(tmp_path),
        embedding_function=HashEmbeddings(16),
    )


def _make(settings, tmp_path):
    return create_vector_store_backend(
        settings,
        character_id="char-1",
        character_dir=str(tmp_path),
        embedding_function=HashEmbeddings(16),
    )


def test_backend_defaults_to_chroma(tmp_path):
    backend = _make({}, tmp_path)

    assert isinstance(backend, ChromaBackend)
    assert backend.name == "chroma"


def test_backend_selects_milvus_from_string(tmp_path):
    backend = _make({"vector_store": "milvus"}, tmp_path)

    assert isinstance(backend, MilvusBackend)
    assert backend.name == "milvus"


def test_backend_selects_milvus_from_mapping(tmp_path):
    backend = _make(
        {"vector_store": {"provider": "milvus", "uri": "http://milvus:19530"}},
        tmp_path,
    )

    assert isinstance(backend, MilvusBackend)
    # A remote uri means no local Milvus Lite file is used.
    assert backend._uri == "http://milvus:19530"
    assert backend._local_db is None


def test_milvus_backend_defaults_to_local_lite_file(tmp_path):
    backend = _make({"vector_store": "milvus"}, tmp_path)

    assert backend._local_db is not None
    assert backend._local_db.suffix == ".db"
    assert "milvus" in backend._local_db.parts


def test_unknown_backend_raises(tmp_path):
    with pytest.raises(ValueError, match="unknown RAG vector store backend"):
        _make({"vector_store": "pinecone"}, tmp_path)


def test_l2_similarity_is_normalized_and_monotonic():
    assert _l2_similarity(0.0) == 1.0
    assert _l2_similarity(-5.0) == 1.0  # clamps negative distances
    assert 0.0 < _l2_similarity(10.0) < _l2_similarity(1.0) < 1.0


def test_safe_collection_name_is_portable():
    # Sanitized, prefixed, and valid for both Chroma and Milvus.
    assert safe_collection_name("角色-A/1") == "cv_A_1"
    assert safe_collection_name("") == "cv_default"
    assert len(safe_collection_name("x" * 1000)) <= 512


def test_milvus_remote_backend_targets_character_collection(tmp_path):
    backend = _remote_milvus(tmp_path, "hero-42")

    assert backend._collection_name == safe_collection_name("hero-42")
    assert backend._collection_name != "cv_default"


@pytest.mark.asyncio
async def test_delete_character_index_drops_character_collection(tmp_path, monkeypatch):
    # Regression: the drop must run against the character's own collection, not
    # the empty-id "cv_default" collection, so remote Milvus indexes are removed.
    engine = RAGEngine({})
    captured: dict = {}

    class _FakeBackend:
        def drop(self) -> None:
            captured["dropped"] = True

    def _fake_backend(character_id: str, character_dir: str):
        captured["character_id"] = character_id
        return _FakeBackend()

    monkeypatch.setattr(engine, "_backend", _fake_backend)

    await engine.delete_character_index("hero-42", str(tmp_path))

    assert captured["character_id"] == "hero-42"
    assert captured["dropped"] is True


def test_milvus_delete_source_raises_on_false(tmp_path):
    backend = _remote_milvus(tmp_path)

    class _FalseClient:
        col = object()  # collection exists

        def delete(self, expr=None):
            return False  # langchain-milvus returns False on a caught failure

    backend._store = _FalseClient()

    with pytest.raises(RuntimeError, match="Milvus deletion failed"):
        backend.delete_source("source_1")


def test_milvus_delete_source_succeeds_when_not_false(tmp_path):
    backend = _remote_milvus(tmp_path)

    class _OkClient:
        col = object()  # collection exists

        def delete(self, expr=None):
            return {"delete_count": 3}

    backend._store = _OkClient()

    backend.delete_source("source_1")  # should not raise


def test_milvus_delete_source_is_noop_before_collection_exists(tmp_path):
    # Regression: a first-ever index against a remote server has no collection
    # yet, so delete must be skipped rather than raising on the benign
    # "collection not found" False return.
    backend = _remote_milvus(tmp_path)

    class _NoCollectionClient:
        col = None

        def delete(self, expr=None):
            raise AssertionError("delete must not run when the collection is absent")

    backend._store = _NoCollectionClient()

    backend.delete_source("source_1")  # should not raise or call delete


def test_milvus_delete_source_escapes_backslashes_and_quotes(tmp_path):
    # source_id comes from the gRPC request and may contain Windows path
    # separators or quotes. The Milvus boolean expression must still resolve to
    # exactly one well-formed string literal equal to that id.
    import json

    backend = _remote_milvus(tmp_path)
    captured = {}

    class _CaptureClient:
        col = object()  # collection exists

        def delete(self, expr=None):
            captured["expr"] = expr
            return {"delete_count": 1}

    backend._store = _CaptureClient()

    for source_id in (r"dir\report", 'dir\\"final', "trailing\\", 'quote"inside'):
        backend.delete_source(source_id)
        literal = captured["expr"].split(" == ", 1)[1]
        assert json.loads(literal) == source_id
