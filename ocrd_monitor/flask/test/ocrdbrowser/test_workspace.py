from ocrdbrowser import workspace
from test import WORKSPACES


def test__a_workspace_with_mets_xml_is_valid() -> None:
    assert workspace.is_valid(str(WORKSPACES / "a_workspace"))


def test__a_workspace_without_mets_xml_is_invalid() -> None:
    assert not workspace.is_valid(str(WORKSPACES / "invalid_workspace"))


def test__a_workspace_that_does_not_exist_is_not_valid() -> None:
    assert not workspace.is_valid(str(WORKSPACES / "non_existing_directory"))


def test__list_workspaces__returns_valid_workspaces() -> None:
    assert set(workspace.list_all(str(WORKSPACES))) == {
        str(WORKSPACES / "a_workspace"),
        str(WORKSPACES / "another workspace"),
    }
