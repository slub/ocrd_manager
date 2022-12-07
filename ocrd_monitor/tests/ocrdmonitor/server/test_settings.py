from pathlib import Path
from typing import Any, Generator, Type

import pytest
from pydantic import BaseModel

from ocrdbrowser import SubProcessOcrdBrowserFactory, DockerOcrdBrowserFactory
from ocrdmonitor.server.settings import (
    OcrdBrowserSettings,
    OcrdControllerSettings,
    Settings,
)

CURRENT_DIR = Path(__file__).parent
ENV_FILE = CURRENT_DIR / ".test.env"


ENV_TEMPLATE = {
    "browser_workspace_dir": "OCRD_BROWSER__WORKSPACE_DIR={}",
    "browser_mode": "OCRD_BROWSER__MODE={}",
    "browser_public_port": "OCRD_BROWSER__PUBLIC_PORT={}",
    "browser_port_range": "OCRD_BROWSER__PORT_RANGE={}",
    "controller_job_dir": "OCRD_CONTROLLER__JOB_DIR={}",
    "controller_host": "OCRD_CONTROLLER__HOST={}",
    "controller_user": "OCRD_CONTROLLER__USER={}",
    "controller_port": "OCRD_CONTROLLER__PORT={}",
    "controller_keyfile": "OCRD_CONTROLLER__KEYFILE={}",
}


class DefaultTestEnv(BaseModel):
    browser_workspace_dir: str = "path/to/workdir"
    browser_mode: str = "native"
    browser_public_port: str = "8085"
    browser_port_range: str = "[9000, 9100]"
    controller_job_dir: str = "path/to/jobdir"
    controller_host: str = "controller.ocrdhost.com"
    controller_user: str = "controller_user"
    controller_port: str = "22"
    controller_keyfile: str = ".ssh/id_rsa"


def write_env_file(env_dict: dict[str, str]) -> Path:
    out = ""
    for k, v in env_dict.items():
        out += ENV_TEMPLATE[k].format(v) + "\n"

    ENV_FILE.touch(exist_ok=True)
    ENV_FILE.write_text(out)

    return ENV_FILE


@pytest.fixture(scope="module", autouse=True)
def env_file_auto_cleanup() -> Generator[None, None, None]:
    yield

    ENV_FILE.unlink(missing_ok=True)


def test__can_parse_env_file() -> None:
    env = DefaultTestEnv()
    env_file = write_env_file(env.dict())

    sut = Settings(_env_file=env_file)

    assert sut == Settings(
        ocrd_browser=OcrdBrowserSettings(
            mode=env.browser_mode,
            workspace_dir=Path(env.browser_workspace_dir),
            public_port=int(env.browser_public_port),
            port_range=(9000, 9100),
        ),
        ocrd_controller=OcrdControllerSettings(
            job_dir=env.controller_job_dir,
            host=env.controller_host,
            user=env.controller_user,
            port=int(env.controller_port),
            keyfile=Path(env.controller_keyfile),
        ),
    )


@pytest.mark.parametrize(
    argnames=["mode", "factory_type"],
    argvalues=[
        ("native", SubProcessOcrdBrowserFactory),
        ("docker", DockerOcrdBrowserFactory),
    ],
)
def test__browser_settings__produces_matching_factory_for_selected_mode(
    mode: str, factory_type: Type[Any]
) -> None:
    env = DefaultTestEnv(browser_mode=mode)
    env_file = write_env_file(env.dict())

    sut = Settings(_env_file=env_file)

    actual = sut.ocrd_browser.factory()
    assert isinstance(actual, factory_type)
