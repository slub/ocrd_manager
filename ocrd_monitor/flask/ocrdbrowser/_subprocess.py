from __future__ import annotations

import subprocess as sp
from shutil import which
import os
from typing import Optional

from ocrdbrowser import OcrdBrowser

from ._port import Port


class SubProcessOcrdBrowser:
    def __init__(self, port: str, localport: Port, owner: str, workspace: str) -> None:
        self._port = port
        self._localport = localport
        self._owner = owner
        self._workspace = workspace
        self._process: Optional[sp.Popen[bytes]] = None

    def address(self) -> str:
        # as long as we do not have a reverse proxy on BW_PORT,
        # we must map the local port range to the exposed range
        # (we use 8085 as fixed start of the internal port range,
        #  and map to the runtime corresponding external port)
        localport = self._localport.get()
        return str(int(self._port) + localport - 8085)

    def workspace(self) -> str:
        return self._workspace

    def owner(self) -> str:
        return self._owner

    def start(self) -> None:
        browse_ocrd = which("browse-ocrd")
        if not browse_ocrd:
            raise FileNotFoundError("Could not find browse-ocrd executable")
        localport = self._localport.get()
        # broadwayd (which uses WebSockets) only allows a single client at a time
        # (disconnecting concurrent connections), hence we must start a new daemon
        # for each new browser session
        # broadwayd starts counting virtual X displays from port 8080 as :0
        displayport = str(localport - 8080)
        environment = dict(os.environ)
        environment['GDK_BACKEND'] = 'broadway'
        environment['BROADWAY_DISPLAY'] = ':' + displayport

        self._process = sp.Popen(
            ' '.join([
                "broadwayd", ":" + displayport + " &",
                browse_ocrd, self._workspace + '/mets.xml ;',
                "kill $!"
            ]),
            shell=True, env=environment
        )

    def stop(self) -> None:
        if self._process:
            self._process.terminate()
            self._localport.release()


class SubProcessOcrdBrowserFactory:
    def __init__(self, port: str, available_ports: Set[int]) -> None:
        self._port = port
        self._available_ports = available_ports

    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        return SubProcessOcrdBrowser(
            self._port, Port(self._available_ports), owner, workspace_path
        )
