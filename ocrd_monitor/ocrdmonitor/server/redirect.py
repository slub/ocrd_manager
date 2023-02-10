from __future__ import annotations

from pathlib import Path
from typing import Callable

from ocrdbrowser import OcrdBrowser


def removeprefix(string: str, prefix: str) -> str:
    def __removeprefix(prefix: str) -> str:
        if string.startswith(prefix):
            len_prefix = len(prefix)
            return string[len_prefix:]

        return string

    _removeprefix: Callable[[str], str] = getattr(
        string, "removeprefix", __removeprefix
    )
    return _removeprefix(prefix)


def removesuffix(string: str, suffix: str) -> str:
    def __removesuffix(suffix: str) -> str:
        if string.endswith(suffix):
            len_suffix = len(suffix)
            return string[-len_suffix:]

        return string

    _removesuffix: Callable[[str], str] = getattr(
        string, "removesuffix", __removesuffix
    )

    return _removesuffix(suffix)


class BrowserRedirect:
    def __init__(self, workspace: Path, browser: OcrdBrowser) -> None:
        self._workspace = workspace
        self._browser = browser

    @property
    def browser(self) -> OcrdBrowser:
        return self._browser

    @property
    def workspace(self) -> Path:
        return self._workspace

    def redirect_url(self, url: str) -> str:
        url = removeprefix(url, str(self._workspace))
        url = removeprefix(url, "/")
        address = removesuffix(self._browser.address(), "/")
        return removesuffix(address + "/" + url, "/")

    def matches(self, path: str) -> bool:
        return path.startswith(str(self.workspace))


class RedirectMap:
    def __init__(self) -> None:
        self._redirects: dict[str, set[BrowserRedirect]] = {}

    def add(
        self, session_id: str, workspace: Path, server: OcrdBrowser
    ) -> BrowserRedirect:
        try:
            redirect = self.get(session_id, workspace)
            return redirect
        except KeyError:
            redirect = BrowserRedirect(workspace, server)
            self._redirects.setdefault(session_id, set()).add(redirect)
            return redirect

    def remove(self, session_id: str, workspace: Path) -> None:
        redirect = self.get(session_id, workspace)
        self._redirects[session_id].remove(redirect)

    def get(self, session_id: str, workspace: Path) -> BrowserRedirect:
        redirect = next(
            (
                redirect
                for redirect in self._redirects.get(session_id, set())
                if redirect.matches(str(workspace))
            ),
            None,
        )

        return self._instance_or_raise(redirect)

    def _instance_or_raise(self, redirect: BrowserRedirect | None) -> BrowserRedirect:
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
