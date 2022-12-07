from pathlib import Path


def from_path(log_path: Path) -> str:
    if log_path.is_dir():
        log_path = log_path / "ocrd.log"
    return log_path.read_text()


def has_logs(log_path: Path) -> bool:
    if log_path.is_file():
        return True

    return (log_path / "ocrd.log").exists()
