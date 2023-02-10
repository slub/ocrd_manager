from __future__ import annotations

import asyncio

from fastapi import Response
from ocrdbrowser import Channel
from requests import request

from .redirect import BrowserRedirect


def forward(redirect: BrowserRedirect, url: str) -> Response:
    redirect_url = redirect.redirect_url(url)
    response = request("GET", redirect_url, allow_redirects=False)
    return Response(
        content=response.content,
        status_code=response.status_code,
        headers=response.headers,
    )


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
