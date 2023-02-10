from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from ocrdbrowser import ChannelClosed, OcrdBrowserFactory
from ocrdmonitor.server.settings import OcrdBrowserSettings

from tests.ocrdbrowser.browserdoubles import BrowserSpy, BrowserSpyFactory, ChannelDummy
from tests.ocrdmonitor.server import scraping
from tests.ocrdmonitor.server.fixtures import WORKSPACE_DIR


@pytest.fixture
def browser_spy(monkeypatch: pytest.MonkeyPatch) -> BrowserSpy:
    browser_spy = BrowserSpy()

    def factory(_: OcrdBrowserSettings) -> OcrdBrowserFactory:
        return BrowserSpyFactory(browser_spy)

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


def test__opened_workspace__when_socket_disconnects_on_broadway_side_while_viewing__shuts_down_browser(
    browser_spy: BrowserSpy,
    app: TestClient,
) -> None:
    class DisconnectingChannel:
        async def send_bytes(self, data: bytes) -> None:
            raise ChannelClosed()

        async def receive_bytes(self) -> bytes:
            raise ChannelClosed()

    browser_spy.channel = DisconnectingChannel()
    _ = app.get("/workspaces/open/a_workspace")

    with app.websocket_connect("/workspaces/view/a_workspace/socket"):
        pass

    assert browser_spy.running is False
