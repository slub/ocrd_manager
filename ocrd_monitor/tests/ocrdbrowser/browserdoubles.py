from __future__ import annotations

from contextlib import asynccontextmanager
from textwrap import dedent
from typing import AsyncGenerator

from ocrdbrowser import Channel, OcrdBrowser


class ChannelDummy:
    async def send_bytes(self, data: bytes) -> None:
        pass

    async def receive_bytes(self) -> bytes:
        return bytes()


class BrowserSpy:
    def __init__(
        self,
        owner: str = "",
        workspace_path: str = "",
        address: str = "",
        running: bool = False,
        channel: Channel | None = None,
    ) -> None:
        self.running = running
        self._address = address
        self.owner_name = owner
        self.workspace_path = workspace_path
        self.channel = channel or ChannelDummy()

    def address(self) -> str:
        return self._address

    def workspace(self) -> str:
        return self.workspace_path

    def owner(self) -> str:
        return self.owner_name

    def start(self) -> None:
        self.running = True

    def stop(self) -> None:
        self.running = False

    @asynccontextmanager
    async def open_channel(self) -> AsyncGenerator[Channel, None]:
        yield self.channel

    def __repr__(self) -> str:
        return dedent(
            f"""
        BrowserSpy:
            workspace: {self.workspace()}
            owner: {self.owner()}
            running: {self.running}
        """
        )


class BrowserSpyFactory:
    def __init__(self, *processes: BrowserSpy) -> None:
        self.proc_iter = iter(processes)

    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        browser = next(self.proc_iter, BrowserSpy())
        browser.owner_name = owner
        browser.workspace_path = workspace_path
        return browser
