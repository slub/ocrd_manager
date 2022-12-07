from pathlib import Path
from typing import Generator

import pytest
import ocrdmonitor.readlogs as readlogs

CURRENT_DIR = Path(__file__).parent
LOGS_DIR = CURRENT_DIR / "logs"
LOG_FILE = LOGS_DIR / "ocrd.log"
LOG_CONTENT = "some log content"


@pytest.fixture(autouse=True)
def prepare_logs() -> Generator[None, None, None]:
    LOGS_DIR.mkdir(exist_ok=True)
    LOG_FILE.touch(exist_ok=True)
    LOG_FILE.write_text(LOG_CONTENT)

    yield

    LOG_FILE.unlink(missing_ok=True)
    LOGS_DIR.rmdir()


@pytest.mark.parametrize("path", [LOG_FILE, LOGS_DIR])
def test__given_a_path__reads_logs(path: Path) -> None:
    actual = readlogs.from_path(path)

    assert actual == LOG_CONTENT


def test__given_a_dir_path_with_log_file__has_logs_is_true() -> None:
    actual = readlogs.has_logs(LOGS_DIR)

    assert actual is True


def test__given_a_dir_path_without_log_file__has_logs_is_false() -> None:
    LOG_FILE.unlink()
    actual = readlogs.has_logs(LOGS_DIR)

    assert actual is False


def test__given_a_file_path__has_logs_is_true() -> None:
    actual = readlogs.has_logs(LOG_FILE)

    assert actual is True