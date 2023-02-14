from __future__ import annotations

from typing import Optional, Set


class NoPortsAvailableError(RuntimeError):
    pass


class Port:
    def __init__(self, available_ports: Set[int]) -> None:
        self._available_ports = available_ports
        self._port: Optional[int] = self._try_pop()

    def get(self) -> int:
        return self._port or self._try_pop()

    def release(self) -> None:
        if not self._port:
            return
        self._available_ports.add(self._port)
        self._port = None

    def _try_pop(self) -> int:
        # FIXME: check if port is still free
        try:
            return self._available_ports.pop()
        except KeyError as err:
            raise NoPortsAvailableError() from err

    def __str__(self) -> str:
        return str(self._port)
