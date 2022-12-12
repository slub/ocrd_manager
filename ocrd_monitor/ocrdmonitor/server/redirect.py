from pathlib import Path
from typing import Protocol


class WorkspaceServer(Protocol):
    def address(self) -> str:
        ...


class WorkspaceRedirect:
    def __init__(self, workspace: Path, server: WorkspaceServer) -> None:
        self._workspace = workspace
        self._server = server

    @property
    def workspace(self) -> Path:
        return self._workspace

    def redirect_url(self, url: str) -> str:
        url = url.removeprefix(str(self._workspace)).removeprefix("/")
        address = self._server.address().removesuffix("/")
        return (address + "/" + url).removesuffix("/")

    def matches(self, path: str) -> bool:
        return path.startswith(str(self.workspace))


class RedirectMap:
    def __init__(self) -> None:
        self._redirects: dict[str, set[WorkspaceRedirect]] = {}

    def add(
        self, session_id: str, workspace: Path, server: WorkspaceServer
    ) -> WorkspaceRedirect:
        try:
            redirect = self.get(session_id, workspace)
            return redirect
        except KeyError:
            redirect = WorkspaceRedirect(workspace, server)
            self._redirects.setdefault(session_id, set()).add(redirect)
            return redirect

    def remove(self, session_id: str, workspace: Path) -> None:
        redirect = self.get(session_id, workspace)
        self._redirects[session_id].remove(redirect)

    def get(self, session_id: str, workspace: Path) -> WorkspaceRedirect:
        redirect = next(
            (
                redirect
                for redirect in self._redirects.get(session_id, set())
                if redirect.matches(str(workspace))
            ),
            None,
        )

        return self._instance_or_raise(redirect)

    def _instance_or_raise(
        self, redirect: WorkspaceRedirect | None
    ) -> WorkspaceRedirect:
        if redirect is None:
            raise KeyError("No redirect found")

        return redirect

    def has_redirect_to_workspace(self, session_id: str, workspace: Path) -> bool:
        try:
            self.get(session_id, workspace)
            return True
        except KeyError:
            return False

    def __contains__(self, session_and_workspace: tuple[str, Path]) -> bool:
        session_id, workspace = session_and_workspace
        return self.has_redirect_to_workspace(session_id, workspace)
