import subprocess as sp
from shutil import which
from typing import Optional

from ocrdbrowser import OcrdBrowser

from ._port import Port


class SubProcessOcrdBrowser:
    def __init__(self, host: str, port: Port, owner: str, workspace: str) -> None:
        self._host = host
        self._port = port
        self._owner = owner
        self._workspace = workspace
        self._process: Optional[sp.Popen[bytes]] = None

    def address(self) -> str:
        return f"{self._host}:{self._port}"

    def workspace(self) -> str:
        return self._workspace

    def owner(self) -> str:
        return self._owner

    def start(self) -> None:
        browse_ocrd = which("browse-ocrd")
        if not browse_ocrd:
            raise FileNotFoundError("Could not find browse-ocrd executable")

        self._process = sp.Popen(
            [
                browse_ocrd,
                "--display",
                f"{self._host}:{self._port.get() - 8080}",
                self._workspace,
            ]
        )

    def stop(self) -> None:
        if self._process:
            self._process.terminate()
            self._port.release()


class SubProcessOcrdBrowserFactory:
    def __init__(self, host: str, available_ports: set[int]) -> None:
        self._host = host
        self._available_ports = available_ports

    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        return SubProcessOcrdBrowser(
            self._host, Port(self._available_ports), owner, workspace_path
        )
