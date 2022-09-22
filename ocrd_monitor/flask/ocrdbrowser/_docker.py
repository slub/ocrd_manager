from __future__ import annotations

import logging
import os.path as path
import subprocess as sp
from typing import Any

from ._browser import OcrdBrowser
from ._port import Port

_docker_run = "docker run --rm -d --name {} -v {}:/data -p {}:8085 ocrd-browser:latest"
_docker_stop = "docker stop {}"


def _run_command(cmd: str, *args: Any) -> sp.CompletedProcess[bytes]:
    command = cmd.format(*args).split()
    return sp.run(command)


class DockerOcrdBrowser:
    def __init__(self, host: str, port: Port, owner: str, workspace: str) -> None:
        self._host = host
        self._port = port
        self._owner = owner
        self._workspace = path.abspath(workspace)

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

    def stop(self) -> None:
        cmd = _run_command(
            _docker_stop, self._container_name(), self.workspace(), self._port.get()
        )
        cmd.check_returncode()
        self._port.release()

    def _container_name(self) -> str:
        workspace = path.basename(self.workspace())
        return f"ocrd-browser-{self.owner()}-{workspace}"


class DockerOcrdBrowserFactory:
    def __init__(self, host: str, available_ports: set[int]) -> None:
        self._host = host
        self._ports = available_ports

    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        return DockerOcrdBrowser(self._host, Port(self._ports), owner, workspace_path)
