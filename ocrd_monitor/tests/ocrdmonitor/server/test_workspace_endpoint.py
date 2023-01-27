import pytest
from fastapi.testclient import TestClient
from ocrdbrowser import OcrdBrowserFactory
from ocrdmonitor.server.app import create_app
from ocrdmonitor.server.settings import OcrdBrowserSettings

from tests.ocrdbrowser.test_launch import BrowserSpy, browser_spy_factory
from tests.ocrdmonitor.server import scraping
from tests.ocrdmonitor.server.fixtures import WORKSPACE_DIR, create_settings


def test__workspaces__shows_the_workspace_names_starting_from_workspace_root() -> None:
    settings = create_settings()
    sut = TestClient(create_app(settings))

    result = sut.get("/workspaces")

    texts = scraping.parse_texts(result.content, "li > a")
    assert set(texts) == {"a_workspace", "another workspace", "nested/workspace"}


def test__open_workspace__passes_full_workspace_path_to_ocrdbrowser(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    browser_spy = BrowserSpy()

    def factory(_: OcrdBrowserSettings) -> OcrdBrowserFactory:
        return browser_spy_factory(browser_spy)

    settings = create_settings()
    monkeypatch.setattr(OcrdBrowserSettings, "factory", factory)

    sut = TestClient(create_app(settings))

    _ = sut.get("/workspaces/open/a_workspace")

    assert browser_spy.running is True
    assert browser_spy.workspace() == str(WORKSPACE_DIR / "a_workspace")
