from test import WORKSPACES
from test.ocrdbrowser.test_launch import BrowserSpy, browser_spy_factory
from test.ocrdbrowser_server import WORKSPACE_VIEW_ROUTE, WORKSPACE_VIEW_URL
from test.ocrdbrowser_server.run_server import run_flask, run_flask_with_browser_fake

import ocrdbrowser
from flask.testing import FlaskClient
from ocrdbrowser import NoPortsAvailableError
from playwright.sync_api import Page, expect

from app import create_app


def make_client(*browsers: BrowserSpy) -> FlaskClient:
    factory = browser_spy_factory(*browsers)
    app = create_app(factory, str(WORKSPACES))
    return app.test_client()


def test_opening_a_preview_page__spawns_a_browser_for_user_in_workspace() -> None:
    spy = BrowserSpy()
    client = make_client(spy)

    _ = client.get(WORKSPACE_VIEW_ROUTE + "/a_workspace")

    assert spy.running is True
    assert spy.workspace_path == str(WORKSPACES / "a_workspace")


def test_given_workspace_opened__when_viewing_different_workspace__stops_process_for_first_one() -> None:
    first_spy = BrowserSpy()
    second_spy = BrowserSpy()
    client = make_client(first_spy, second_spy)

    _ = client.get(WORKSPACE_VIEW_ROUTE + "/a_workspace")
    _ = client.get(WORKSPACE_VIEW_ROUTE + "/another workspace")

    assert first_spy.running is False
    assert second_spy.running is True
    assert second_spy.workspace_path == str(WORKSPACES / "another workspace")


def test_given_workspace_opened__when_viewing_same_workspace__does_not_start_new_process() -> None:
    first_spy = BrowserSpy()
    must_not_run = BrowserSpy()
    client = make_client(first_spy, must_not_run)

    _ = client.get(WORKSPACE_VIEW_ROUTE + "/a_workspace")
    _ = client.get(WORKSPACE_VIEW_ROUTE + "/a_workspace")

    assert first_spy.running is True
    assert first_spy.workspace_path == str(WORKSPACES / "a_workspace")
    assert must_not_run.running is False


def test__opening_same_workspace_with_different_users__starts_two_browsers() -> None:
    first, second = BrowserSpy(), BrowserSpy()
    factory = browser_spy_factory(first, second)
    app = create_app(factory, str(WORKSPACES))
    first_client = app.test_client()
    second_client = app.test_client()

    _ = first_client.get(WORKSPACE_VIEW_ROUTE + "/a_workspace")
    _ = second_client.get(WORKSPACE_VIEW_ROUTE + "/a_workspace")

    assert first.running is True
    assert second.running is True


def test__opening_a_workspace__shows_an_iframe_with_the_workspace(page: Page) -> None:
    with run_flask_with_browser_fake(str(WORKSPACES)):
        page.goto(f"{WORKSPACE_VIEW_URL}/a_workspace")
        expect(page.frame_locator("iframe").locator("#content")).to_contain_text(
            str(WORKSPACES / "a_workspace")
        )


def test__opening_invalid_workspace__shows_an_error_message(page: Page) -> None:
    with run_flask(workspace_dir=str(WORKSPACES)):
        page.goto(f"{WORKSPACE_VIEW_URL}/invalid_workspace")
        expect(page.locator("div.flash")).to_have_text("Not a valid workspace")


def test__when_no_ports_available_for_browser__shows_an_error_message(
    page: Page,
) -> None:
    with run_flask(no_ports_browser_factory, str(WORKSPACES)):
        page.goto(f"{WORKSPACE_VIEW_URL}/a_workspace")
        expect(page.locator("div.flash")).to_have_text(
            "Not enough resources to open the workspace"
        )


def no_ports_browser_factory(
    owner: str, workspace_path: str
) -> ocrdbrowser.OcrdBrowser:
    raise NoPortsAvailableError()
