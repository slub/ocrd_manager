import multiprocessing as mp
from typing import Any

import uvicorn
from fastapi import FastAPI, Response, WebSocket
from fastapi.responses import HTMLResponse

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
        while True:
            socket_log.put(await websocket.receive_text())

    uvicorn.run(app, host="localhost", port=7000)


class BroadwayFake:
    def __init__(self, workspace: str) -> None:
        self._socket_log: mp.Queue[str] = mp.Queue()
        self._complete_log: list[str] = []
        self._workspace = workspace

        self._process: mp.Process | None = None

    def __enter__(self) -> "BroadwayFake":
        self.launch()
        return self

    def __exit__(self, *args: Any, **kwargs: Any) -> None:
        self.shutdown()

    @property
    def is_running(self) -> bool:
        return self._process is not None

    def launch(self) -> None:
        if self.is_running:
            return

        self._process = mp.Process(
            target=_run_app,
            args=(self._workspace, self._socket_log),
        )

        self._process.start()

    def shutdown(self) -> None:
        if not self.is_running:
            return

        self._process.kill()  # type: ignore
        self._process = None

    @property
    def socket_log(self) -> list[str]:
        while not self._socket_log.empty():
            self._complete_log.append(self._socket_log.get())

        return list(self._complete_log)
