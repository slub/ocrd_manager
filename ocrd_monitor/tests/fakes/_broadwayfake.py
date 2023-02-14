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


def _run_app(workspace: str) -> None:
    app = FastAPI()

    @app.get("/")
    def index() -> Response:
        return HTMLResponse(content=html_template.format(workspace=workspace))

    @app.websocket("/socket")
    async def socket(websocket: WebSocket) -> None:
        await websocket.accept()
        try:
            while True:
                echo = await websocket.receive_bytes()
                await websocket.send_bytes(echo)
        except WebSocketDisconnect:
            pass

    uvicorn.run(app, host="localhost", port=7000)


def broadway_fake(workspace: str) -> BackgroundProcess:
    process = BackgroundProcess(_run_app, workspace)

    return process
