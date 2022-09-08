from pathlib import Path


def is_valid(workspace: str) -> bool:
    return (Path(workspace) / "mets.xml").exists()


def list_all(path: str) -> list[str]:
    return [
        str(workspace) for workspace in Path(path).iterdir() if is_valid(str(workspace))
    ]
