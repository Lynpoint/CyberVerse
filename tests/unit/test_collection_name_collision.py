"""Regression: pure non-ASCII character ids must not all collide on cv_default."""

from inference.rag.vector_store import safe_collection_name


def test_distinct_chinese_ids_do_not_share_a_collection():
    # Chinese names are common character ids in CyberVerse. The sanitizer
    # dropped every non-ASCII character, so "晴天", "雨天" and "张伟" all
    # sanitized to an empty string and fell back to "cv_default". Distinct
    # characters then silently shared one RAG index and cross-contaminated
    # each other's knowledge sources.
    names = ["晴天", "雨天", "张伟", "李娜"]
    collections = [safe_collection_name(name) for name in names]

    assert len(set(collections)) == len(names)
    assert "cv_default" not in collections


def test_empty_id_still_uses_default_collection():
    # An actually empty id keeps the historical default name so existing
    # collections created for empty ids remain reachable.
    assert safe_collection_name("") == "cv_default"


def test_generated_names_remain_portable():
    for name in ["晴天", "雨天", "角色-A/1", "x" * 1000]:
        value = safe_collection_name(name)
        assert 3 <= len(value) <= 512
        assert all(ch.isalnum() or ch == "_" for ch in value)
