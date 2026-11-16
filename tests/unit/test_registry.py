import pytest

from inference.core.registry import PluginRegistry
from inference.core.types import PluginConfig
from inference.plugins.base import CyberVersePlugin


class MockPlugin(CyberVersePlugin):
    name = "mock.test"
    initialized = False
    shut_down = False

    async def initialize(self, config: PluginConfig) -> None:
        self.initialized = True
        self.config = config

    async def shutdown(self) -> None:
        self.shut_down = True


class AnotherPlugin(CyberVersePlugin):
    name = "mock.another"

    async def initialize(self, config: PluginConfig) -> None:
        pass

    async def shutdown(self) -> None:
        pass


def test_register_and_list():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    assert "mock.test" in registry.registered_names


def test_register_duplicate_raises():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    with pytest.raises(ValueError, match="already registered"):
        registry.register("mock.test", MockPlugin)


def test_unregister():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    registry.unregister("mock.test")
    assert "mock.test" not in registry.registered_names


@pytest.mark.asyncio
async def test_initialize():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    config = PluginConfig(plugin_name="mock.test", params={"foo": "bar"})
    instance = await registry.initialize("mock.test", config)
    assert instance.initialized is True
    assert instance.config.params["foo"] == "bar"
    assert "mock.test" in registry.initialized_names


@pytest.mark.asyncio
async def test_initialize_unknown_raises():
    registry = PluginRegistry()
    with pytest.raises(KeyError, match="not registered"):
        await registry.initialize("unknown", PluginConfig(plugin_name="unknown"))


@pytest.mark.asyncio
async def test_get():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    await registry.initialize("mock.test", PluginConfig(plugin_name="mock.test"))
    plugin = registry.get("mock.test")
    assert isinstance(plugin, MockPlugin)


def test_get_uninitialized_raises():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    with pytest.raises(KeyError, match="not initialized"):
        registry.get("mock.test")


@pytest.mark.asyncio
async def test_get_by_category():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    await registry.initialize("mock.test", PluginConfig(plugin_name="mock.test"))
    plugin = registry.get_by_category("mock")
    assert isinstance(plugin, MockPlugin)
    assert registry.get_by_category("nonexistent") is None


@pytest.mark.asyncio
async def test_initialize_all():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    registry.register("mock.another", AnotherPlugin)
    configs = {
        "mock.test": PluginConfig(plugin_name="mock.test"),
        "mock.another": PluginConfig(plugin_name="mock.another"),
    }
    await registry.initialize_all(configs)
    assert len(registry.initialized_names) == 2


@pytest.mark.asyncio
async def test_shutdown_all():
    registry = PluginRegistry()
    registry.register("mock.test", MockPlugin)
    await registry.initialize("mock.test", PluginConfig(plugin_name="mock.test"))
    plugin = registry.get("mock.test")
    await registry.shutdown_all()
    assert plugin.shut_down is True
    assert len(registry.initialized_names) == 0


class FailingShutdownPlugin(MockPlugin):
    async def shutdown(self) -> None:
        self.shut_down = True
        raise RuntimeError("close failed")


@pytest.mark.asyncio
async def test_shutdown_all_continues_after_a_failure_and_clears():
    """One plugin's shutdown raising must not leave the others unclosed or
    keep partly-shut-down instances registered."""
    registry = PluginRegistry()
    registry.register("a.bad", FailingShutdownPlugin)
    registry.register("a.good", MockPlugin)
    await registry.initialize("a.bad", PluginConfig(plugin_name="a.bad"))
    await registry.initialize("a.good", PluginConfig(plugin_name="a.good"))
    bad = registry.get("a.bad")
    good = registry.get("a.good")

    with pytest.raises(RuntimeError, match="close failed"):
        await registry.shutdown_all()

    assert bad.shut_down is True
    assert good.shut_down is True
    assert len(registry.initialized_names) == 0
