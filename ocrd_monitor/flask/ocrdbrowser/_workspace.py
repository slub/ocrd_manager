from __future__ import annotations

from pathlib import Path
from typing import List
from functools import lru_cache

def is_valid(workspace: str) -> bool:
    return (Path(workspace) / "mets.xml").exists()

@lru_cache(maxsize=1)
def list_all(path: str) -> List[str]:
    # recursively enumerate METS file paths (excluding .backup subdirs)
    return [
        str(workspace) for workspace in Path(path).iterdir() if is_valid(str(workspace))
    ]
