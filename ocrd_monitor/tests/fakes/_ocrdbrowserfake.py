from ocrdbrowser import OcrdBrowser
from ._backgroundprocess import BackgroundProcess
from ._broadwayfake import broadway_fake


class OcrdBrowserFake:
    def __init__(self, owner: str = "", workspace: str = "") -> None:
        self._owner: str = owner
        self._workspace: str = workspace
        self._browser = broadway_fake(workspace)
        self._running = False

    def set_owner_and_workspace(self, owner: str, workspace: str) -> None:
        self._owner = owner
        self._workspace = workspace
        self._browser = broadway_fake(workspace)

    def address(self) -> str:
        return "http://localhost:7000"

    def owner(self) -> str:
        return self._owner

    def workspace(self) -> str:
        return self._workspace

    def start(self) -> None:
        self._running = True
        self._browser.launch()

    def stop(self) -> None:
        self._running = False
        self._browser.shutdown()

    @property
    def broadway_server(self) -> BackgroundProcess:
        return self._browser

    @property
    def is_running(self) -> bool:
        return self._running

    @property
    def is_server_running(self) -> bool:
        return self._browser.is_running


class OcrdBrowserFakeFactory:
    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        return OcrdBrowserFake(owner, workspace_path)
