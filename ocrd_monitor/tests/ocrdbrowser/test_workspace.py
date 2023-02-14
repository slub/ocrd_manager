from pathlib import Path

from ocrdbrowser import workspace

WORKSPACES = Path(__file__).parent.parent / "workspaces"


def test__a_workspace_with_mets_xml_is_valid() -> None:
    assert workspace.is_valid(str(WORKSPACES / "a_workspace"))


def test__a_nested_workspace__is_valid() -> None:
    assert workspace.is_valid(str(WORKSPACES / "nested" / "workspace"))


def test__a_workspace_without_mets_xml_is_invalid() -> None:
    assert not workspace.is_valid(str(WORKSPACES / "invalid_workspace"))


def test__list_workspaces__returns_valid_workspaces() -> None:
    assert set(workspace.list_all(str(WORKSPACES))) == {
        str(WORKSPACES / "a_workspace"),
        str(WORKSPACES / "another workspace"),
        str(WORKSPACES / "nested" / "workspace"),
    }
