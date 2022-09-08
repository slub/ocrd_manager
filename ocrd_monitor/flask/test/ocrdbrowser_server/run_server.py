import multiprocessing as mp
import sys
import time
from contextlib import contextmanager
from multiprocessing import Process
from test.ocrdbrowser_server import URL
from test.ocrdbrowser_server.browserfake.browserprocess import FakeOcrdBrowserFactory
from typing import Generator

from ocrdbrowser import OcrdBrowser, OcrdBrowserFactory

from app import create_app


class DummyOcrdBrowser:
    def address(self) -> str:
        return ""

    def owner(self) -> str:
        return ""

    def workspace(self) -> str:
        return ""

    def start(self) -> None:
        return

    def stop(self) -> None:
        return


class DummyOcrdBrowserFactory:
    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        return DummyOcrdBrowser()


def _run_flask(factory: OcrdBrowserFactory, workspace_dir: str) -> None:
    app = create_app(factory, workspace_dir)
    url, port = URL.split(":")
    app.run(host=url, port=int(port))


@contextmanager
def run_flask(
    process_factory: OcrdBrowserFactory | None = None, workspace_dir: str = "."
) -> Generator[None, None, None]:
    try:
        factory = process_factory or DummyOcrdBrowserFactory()
        server = Process(target=_run_flask, args=(factory, workspace_dir))
        server.start()
        time.sleep(1)

        yield
    finally:
        server.terminate()
        server.join()


def _run_flask_with_browser_fake(workspace_dir: str) -> None:
    import signal

    def do_exit(factory: FakeOcrdBrowserFactory) -> None:
        factory.close()
        sys.exit(0)

    factory = FakeOcrdBrowserFactory()
    signal.signal(signal.SIGTERM, lambda *_, **__: do_exit(factory))
    _run_flask(factory, workspace_dir)


@contextmanager
def run_flask_with_browser_fake(workspace_dir: str) -> Generator[None, None, None]:
    try:
        server = mp.Process(target=_run_flask_with_browser_fake, args=(workspace_dir,))
        server.start()
        time.sleep(1)

        yield
    finally:
        server.terminate()
        server.join()
