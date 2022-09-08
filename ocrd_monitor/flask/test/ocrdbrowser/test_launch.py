import os
from test import WORKSPACES
from textwrap import dedent
from typing import cast

import ocrdbrowser


class BrowserSpy:
    def __init__(
        self, owner: str = "", workspace_path: str = "", running: bool = False
    ) -> None:
        self.running = running
        self.owner_name = owner
        self.workspace_path = workspace_path

    def address(self) -> str:
        return ""

    def workspace(self) -> str:
        return self.workspace_path

    def owner(self) -> str:
        return self.owner_name

    def start(self) -> None:
        self.running = True

    def stop(self) -> None:
        self.running = False

    def __repr__(self) -> str:
        return dedent(
            f"""
        BrowserSpy:
            workspace: {self.workspace()}
            owner: {self.owner()}
            running: {self.running}
        """
        )


class browser_spy_factory:
    def __init__(self, *processes: BrowserSpy) -> None:
        self.proc_iter = iter(processes)

    def __call__(self, owner: str, workspace_path: str) -> ocrdbrowser.OcrdBrowser:
        browser = next(self.proc_iter, BrowserSpy())
        browser.owner_name = owner
        browser.workspace_path = workspace_path
        return browser


def test__workspace__launch__spawns_new_ocrd_browser() -> None:
    owner = "the-owner"
    workspace = str(WORKSPACES / "a_workspace")
    process = ocrdbrowser.launch(workspace, owner, browser_spy_factory())

    process = cast(BrowserSpy, process)
    assert process.running is True
    assert process.owner() == owner
    assert process.workspace() == workspace


def test__workspace__launch_for_different_owners__both_processes_running() -> None:
    factory = browser_spy_factory()

    first_process = ocrdbrowser.launch("first-path", "first-owner", factory)
    second_process = ocrdbrowser.launch(
        "second-path", "second-owner", factory, {first_process}
    )

    processes = {first_process, second_process}
    assert all(cast(BrowserSpy, process).running for process in processes)
    assert {p.owner() for p in processes} == {"first-owner", "second-owner"}
    assert {p.workspace() for p in processes} == {"first-path", "second-path"}


def test__workspace__launch_for_same_owner_and_workspace__does_not_start_new_process() -> None:
    owner = "the-owner"
    workspace = str(WORKSPACES / "a_workspace")
    factory = browser_spy_factory()

    first_process = ocrdbrowser.launch(workspace, owner, factory)
    second_process = ocrdbrowser.launch(workspace, owner, factory, {first_process})

    assert first_process is second_process


def test__relative_workspace_is_same_workspace_as_absolute_workspace() -> None:
    workspace_path = WORKSPACES / "a_workspace"
    rel_path = workspace_path.relative_to(os.getcwd())
    browser = BrowserSpy(owner="a", workspace_path=str(workspace_path))

    assert browser in ocrdbrowser.in_same_workspace(str(rel_path), {browser})
    assert browser not in ocrdbrowser.in_other_workspaces(str(rel_path), {browser})
