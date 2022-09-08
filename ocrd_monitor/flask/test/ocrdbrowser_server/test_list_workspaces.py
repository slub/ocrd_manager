from playwright.sync_api import Page, expect
from test import WORKSPACES
from test.ocrdbrowser_server import WORKSPACE_LIST_URL, WORKSPACE_VIEW_ROUTE

from test.ocrdbrowser_server.run_server import run_flask


def test__the_index_page_shows_a_list_of_available_workspaces(page: Page) -> None:
    with run_flask(workspace_dir=str(WORKSPACES)):
        page.goto(WORKSPACE_LIST_URL)
        workspaces = ["a_workspace", "another workspace"]

        expect(page.locator(".workspace-name")).to_have_text(workspaces)  # type: ignore


def test__following_a_link__leads_to_the_view_route(page: Page) -> None:
    with run_flask(workspace_dir=str(WORKSPACES)):
        page.goto(WORKSPACE_LIST_URL)
        page.locator(".workspace-name").first.click()

        assert page.url.endswith(WORKSPACE_VIEW_ROUTE + "/a_workspace")
