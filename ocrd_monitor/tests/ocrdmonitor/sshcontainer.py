import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Generator

import pytest
from testcontainers.general import DockerContainer

KEYDIR = Path("tests/ocrdmonitor/server/keys")

PS = "ps -o pid --no-headers"


@dataclass
class SSHConfig:
    host: str
    port: int
    user: str
    keyfile: Path


def remove_existing_host_key() -> None:
    subprocess.run("ssh-keygen -R [localhost]:2222", shell=True, check=True)


def configure_container(pub_key: Path) -> DockerContainer:
    return (
        DockerContainer(image="lscr.io/linuxserver/openssh-server:latest")
        .with_bind_ports(2222, 2222)
        .with_env("PUBLIC_KEY", pub_key.read_text())
        .with_env("USER_NAME", "testcontainer")
    )


def get_process_group_from_container(container: DockerContainer) -> int:
    result = container.exec(PS)
    return int(result.output.splitlines()[0].strip())


@pytest.fixture
def ssh_keys() -> Generator[tuple[Path, Path], None, None]:
    KEYDIR.mkdir(parents=True, exist_ok=True)
    private_key = KEYDIR / "id.rsa"
    public_key = KEYDIR / "id.rsa.pub"

    subprocess.run(
        f"ssh-keygen -t rsa -P '' -f {private_key.as_posix()}", shell=True, check=True
    )

    yield private_key, public_key

    private_key.unlink()
    public_key.unlink()


@pytest.fixture
def openssh_server(
    ssh_keys: tuple[Path, Path]
) -> Generator[DockerContainer, None, None]:
    remove_existing_host_key()
    _, public_key = ssh_keys
    with configure_container(public_key) as container:
        time.sleep(1)  # wait for ssh server to start
        yield container

    remove_existing_host_key()
