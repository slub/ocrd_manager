import multiprocessing as mp
import time
from typing import Any

from ocrdbrowser import OcrdBrowser

from .app import create_app


def _run_app(workspace: str, port: int) -> None:
    app = create_app(workspace)
    app.run(port=port)


def _launch_app(workspace: str, port: int) -> mp.Process:
    process = mp.Process(
        target=_run_app, kwargs={"workspace": workspace, "port": port}, name=workspace
    )
    process.start()

    return process


class BrowserProcessFake:
    def __init__(self, owner: str, workspace: str) -> None:
        self._owner = owner
        self._workspace = workspace
        self._process: mp.Process = None  # type: ignore

    def owner(self) -> str:
        return self._owner

    def workspace(self) -> str:
        return self._workspace

    def start(self) -> None:
        self._process = _launch_app(self._workspace, 8001)
        time.sleep(1)

    def stop(self) -> None:
        self._process.terminate()
        self._process.join()

    def address(self) -> str:
        return "http://127.0.0.1:8001"


class FakeOcrdBrowserFactory:
    def __init__(self) -> None:
        self.running_browsers: list[OcrdBrowser] = []

    def __enter__(self) -> "FakeOcrdBrowserFactory":
        return self

    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        browser = BrowserProcessFake(owner, workspace_path)
        self.running_browsers.append(browser)
        return browser

    def __exit__(self, *args: Any, **kwargs: Any) -> None:
        self.close()

    def close(self) -> None:
        for b in self.running_browsers:
            b.stop()
