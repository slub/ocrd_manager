from __future__ import annotations

import uuid
from pathlib import Path

import ocrdbrowser
import ocrdmonitor.server.proxy as proxy
from fastapi import APIRouter, Cookie, Request, Response, WebSocket
from fastapi.templating import Jinja2Templates
from ocrdbrowser import ChannelClosed, OcrdBrowser, OcrdBrowserFactory, workspace
from ocrdmonitor.server.redirect import RedirectMap
from requests.exceptions import ConnectionError


def create_workspaces(
    templates: Jinja2Templates, factory: OcrdBrowserFactory, workspace_dir: Path
) -> APIRouter:

    router = APIRouter(prefix="/workspaces")

    running_browsers: set[OcrdBrowser] = set()
    redirects = RedirectMap()

    @router.get("/", name="workspaces.list")
    def list_workspaces(request: Request) -> Response:
        spaces = [
            Path(space).relative_to(workspace_dir)
            for space in workspace.list_all(workspace_dir)
        ]

        return templates.TemplateResponse(
            "list_workspaces.html.j2",
            {"request": request, "workspaces": spaces},
        )

    @router.get("/open/{workspace:path}", name="workspaces.open")
    def open_workspace(request: Request, workspace: str) -> Response:
        workspace_path = workspace_dir / workspace

        session_id = request.cookies.setdefault("session_id", str(uuid.uuid4()))
        response = templates.TemplateResponse(
            "workspace.html.j2",
            {"request": request, "workspace": workspace},
        )
        response.set_cookie("session_id", session_id)

        browser = launch_browser(session_id, workspace_path)
        redirects.add(session_id, Path(workspace), browser)

        return response

    # NOTE: It is important that the route path here ends with a slash, otherwise
    #       the reverse routing will not work as broadway.js uses window.location
    #       which points to the last component with a trailing slash.
    @router.get("/view/{workspace:path}/", name="workspaces.view")
    def workspace_reverse_proxy(
        request: Request, workspace: str, session_id: str = Cookie(default=None)
    ) -> Response:
        workspace_path = Path(workspace)
        redirect = redirects.get(session_id, workspace_path)
        try:
            return proxy.forward(redirect, str(workspace_path))
        except ConnectionError:
            return templates.TemplateResponse(
                "view_workspace_failed.html.j2",
                {"request": request, "workspace": workspace},
            )

    @router.websocket("/view/{workspace:path}/socket", name="workspaces.view.socket")
    async def workspace_socket_proxy(
        websocket: WebSocket, workspace: Path, session_id: str = Cookie(default=None)
    ) -> None:
        redirect = redirects.get(session_id, workspace)
        await websocket.accept(subprotocol="broadway")
        await communicate_with_browser_until_closed(websocket, redirect.browser)

    async def communicate_with_browser_until_closed(
        websocket: WebSocket, browser: OcrdBrowser
    ) -> None:
        async with browser.open_channel() as channel:
            try:
                while True:
                    await proxy.tunnel(channel, websocket)
            except ChannelClosed:
                browser.stop()

    def launch_browser(session_id: str, workspace: Path) -> OcrdBrowser:
        browser = ocrdbrowser.launch(
            str(workspace),
            session_id,
            factory,
            running_browsers,
        )

        running_browsers.add(browser)
        return browser

    return router
