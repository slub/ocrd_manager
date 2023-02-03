from __future__ import annotations

import asyncio
from types import TracebackType
from typing import Protocol, Sequence, Type, cast

from fastapi import Response
from requests import request
from websockets import client
from websockets.legacy.client import WebSocketClientProtocol
from websockets.typing import Subprotocol

from .redirect import WorkspaceRedirect


class WebSocketAdapter:
    def __init__(
        self, url: str, protocols: Sequence[Subprotocol] | None = None
    ) -> None:
        url = url.replace("http://", "ws://").replace("https://", "wss://")
        self._connection = client.connect(
            url,
            subprotocols=protocols,
            open_timeout=None,
            ping_timeout=None,
            close_timeout=None,
            max_size=2**32,
        )

        self._open_connection: WebSocketClientProtocol | None = None

    async def __aenter__(self) -> "WebSocketAdapter":
        self._open_connection = await self._connection
        return self

    async def __aexit__(
        self,
        exc_type: Type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        if not self._open_connection:
            return

        await self._open_connection.close()
        self._open_connection = None

    async def receive_bytes(self) -> bytes:
        if not self._open_connection:
            return bytes()

        return cast(bytes, await self._open_connection.recv())

    async def send_bytes(self, data: bytes) -> None:
        if not self._open_connection:
            return

        await self._open_connection.send(data)


def forward(redirect: WorkspaceRedirect, url: str) -> Response:
    redirect_url = redirect.redirect_url(url)
    response = request("GET", redirect_url, allow_redirects=False)
    return Response(
        content=response.content,
        status_code=response.status_code,
        headers=response.headers,
    )


class Channel(Protocol):
    async def receive_bytes(self) -> bytes:
        ...

    async def send_bytes(self, data: bytes) -> None:
        ...


async def tunnel(
    source: Channel,
    target: Channel,
    timeout: float = 0.001,
) -> None:
    await _tunnel_one_way(source, target, timeout)
    await _tunnel_one_way(target, source, timeout)


async def _tunnel_one_way(
    source: Channel,
    target: Channel,
    timeout: float,
) -> None:
    try:
        source_data = await asyncio.wait_for(source.receive_bytes(), timeout)
        await target.send_bytes(source_data)
    except asyncio.exceptions.TimeoutError:
        # a timeout is rather common if no data is being sent,
        # so we are simply ignoring this exception
        pass
