from pathlib import Path

from testcontainers.general import DockerContainer

from ocrdmonitor.processstatus import ProcessState
from ocrdmonitor.sshps import process_status
from tests.ocrdmonitor.sshcontainer import (
    get_process_group_from_container,
    SSHConfig,
    KEYDIR,
    # we need to import the fixtures below in order to use them in the test
    ssh_keys,
    openssh_server,
)


def test_ps_over_ssh__returns_list_of_process_status(
    openssh_server: DockerContainer,
) -> None:
    process_group = get_process_group_from_container(openssh_server)

    actual = process_status(
        config=SSHConfig(
            host="localhost",
            port=2222,
            user="testcontainer",
            keyfile=Path(KEYDIR) / "id.rsa",
        ),
        process_group=process_group,
    )

    first_process = actual[0]
    assert first_process.pid == process_group
    assert first_process.state == ProcessState.SLEEPING
