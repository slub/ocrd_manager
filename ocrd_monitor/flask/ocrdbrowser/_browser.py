import sys
from os import path
from typing import Optional, Set
if sys.version_info >= (3, 8):
    from typing import Protocol, TypeAlias
else:
    from typing_extensions import Protocol, TypeAlias


class OcrdBrowser(Protocol):
    def address(self) -> str:
        ...

    def owner(self) -> str:
        ...

    def workspace(self) -> str:
        ...

    def start(self) -> None:
        ...

    def stop(self) -> None:
        ...


class OcrdBrowserFactory(Protocol):
    def __call__(self, owner: str, workspace_path: str) -> OcrdBrowser:
        ...


BrowserProcesses: TypeAlias = Set[OcrdBrowser]


def launch(
    workspace_path: str,
    owner: str,
    browser_factory: OcrdBrowserFactory,
    running_browsers: Optional[BrowserProcesses] = None,
) -> OcrdBrowser:
    running_browsers = running_browsers or set()

    owned_processes = filter_owned(owner, running_browsers)
    in_workspace = in_same_workspace(workspace_path, owned_processes)

    if in_workspace:
        return in_workspace.pop()

    return start_process(browser_factory, workspace_path, owner)


def in_same_workspace(
    workspace_path: str, browser_processes: BrowserProcesses
) -> BrowserProcesses:
    workspace_path = path.abspath(workspace_path)
    return {p for p in browser_processes if p.workspace() == workspace_path}


def in_other_workspaces(
    workspace_path: str, browser_processes: BrowserProcesses
) -> BrowserProcesses:
    workspace_path = path.abspath(workspace_path)
    return {p for p in browser_processes if p.workspace() != workspace_path}


def filter_owned(owner: str, running_processes: BrowserProcesses) -> BrowserProcesses:
    return {p for p in running_processes if p.owner() == owner}


def stop_all(owned_processes: BrowserProcesses) -> None:
    for process in owned_processes:
        process.stop()


def start_process(
    process_factory: OcrdBrowserFactory, workspace_path: str, owner: str
) -> OcrdBrowser:
    process = process_factory(owner, workspace_path)
    process.start()
    return process
