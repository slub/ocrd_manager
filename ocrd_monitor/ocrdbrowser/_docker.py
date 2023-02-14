from __future__ import annotations

import os.path as path
import subprocess as sp
from typing import Any, AsyncContextManager

from ._browser import Channel, OcrdBrowser
from ._port import Port
from ._websocketchannel import WebSocketChannel

_docker_run = "docker run --rm -d --name {} -v {}:/data -p {}:8085 ocrd-browser:latest"
_docker_stop = "docker stop {}"


def _run_command(cmd: str, *args: Any) -> sp.CompletedProcess[str]:
    command = cmd.format(*args).split()
    return sp.run(command, stdout=sp.PIPE, text=True)


class DockerOcrdBrowser:
    def __init__(self, host: str, port: Port, owner: str, workspace: str) -> None:
        self._host = host
        self._port = port
        self._owner = owner
        self._workspace = path.abspath(workspace)
        self.id: str | None = None

    def address(self) -> str:
        return f"{self._host}:{self._port}"

    def workspace(self) -> str:
        return self._workspace

    def owner(self) -> str:
        return self._owner

    def start(self) -> None:
        cmd = _run_command(
            _docker_run, self._container_name(), self._workspace, self._port.get()
        )
        cmd.check_returncode()
        self.id = str(cmd.stdout).strip()

    def stop(self) -> None:
        cmd = _run_command(
            _docker_stop, self._container_name(), self.workspace(), self._port.get()
        )
        cmd.check_returncode()
        self._port.release()
        self.id = None

    def open_channel(self) -> AsyncContextManager[Channel]:
        return WebSocketChannel(self.address() + "/socket")

    def _container_name(self) -> str:
        workspace = path.basename(self.workspace())
        return f"ocrd-browser-{self.owner()}-{workspace}"


class DockerOcrdBrowserFactory:
    def __init__(self, host: str, available_ports: set[int]) -> None:
        self._host = host
        self._ports = available_ports
        self._containers: list[DockerOcrdBrowser] = []

    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        container = DockerOcrdBrowser(
            self._host, Port(self._ports), owner, workspace_path
        )
        self._containers.append(container)
        return container

    def stop_all(self) -> None:
        running_ids = [c.id for c in self._containers if c.id]
        if running_ids:
            _run_command(_docker_stop, " ".join(running_ids))

        self._containers = []
