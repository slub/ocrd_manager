from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from ocrdbrowser import OcrdBrowserFactory
from ocrdmonitor.server.settings import OcrdBrowserSettings

from tests.ocrdbrowser.test_launch import BrowserSpy, browser_spy_factory
from tests.ocrdmonitor.server import scraping
from tests.ocrdmonitor.server.fixtures import WORKSPACE_DIR


@pytest.fixture
def browser_spy(monkeypatch: pytest.MonkeyPatch) -> BrowserSpy:
    browser_spy = BrowserSpy()

    def factory(_: OcrdBrowserSettings) -> OcrdBrowserFactory:
        return browser_spy_factory(browser_spy)

    monkeypatch.setattr(OcrdBrowserSettings, "factory", factory)
    return browser_spy


def test__workspaces__shows_the_workspace_names_starting_from_workspace_root(
    app: TestClient,
) -> None:
    result = app.get("/workspaces")

    texts = scraping.parse_texts(result.content, "li > a")
    assert set(texts) == {"a_workspace", "another workspace", "nested/workspace"}


def test__open_workspace__passes_full_workspace_path_to_ocrdbrowser(
    browser_spy: BrowserSpy,
    app: TestClient,
) -> None:
    _ = app.get("/workspaces/open/a_workspace")

    assert browser_spy.running is True
    assert browser_spy.workspace() == str(WORKSPACE_DIR / "a_workspace")
