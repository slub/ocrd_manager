import multiprocessing as mp

import uvicorn
from fastapi import FastAPI, Response, WebSocket
from fastapi.responses import HTMLResponse
from starlette.websockets import WebSocketDisconnect

from ._backgroundprocess import BackgroundProcess


html_template = """
<!DOCTYPE html>
<html lang="en">
<body>
    <h1>{workspace}</h1>
</body>
</html>
"""


def _run_app(workspace: str, socket_log: mp.Queue) -> None:
    app = FastAPI()

    @app.get("/")
    def index() -> Response:
        return HTMLResponse(content=html_template.format(workspace=workspace))

    @app.websocket("/socket")
    async def socket(websocket: WebSocket) -> None:
        await websocket.accept("broadway")
        try:
            while True:
                socket_log.put(str(await websocket.receive_bytes()))
        except WebSocketDisconnect:
            pass

    uvicorn.run(app, host="localhost", port=7000)


def broadway_fake(workspace: str) -> BackgroundProcess:
    socket_log: mp.Queue[str] = mp.Queue()
    complete_log: list[str] = []
    process = BackgroundProcess(_run_app, workspace, socket_log)

    return process
