from pathlib import Path
import subprocess
from typing import Protocol
from ocrdmonitor.processstatus import ProcessStatus, PS_CMD


class SSHConfig(Protocol):
    host: str
    port: int
    user: str
    keyfile: Path


_SSH = (
    "ssh -o StrictHostKeyChecking=no -i '{keyfile}' -p {port} {user}@{host} '{ps_cmd}'"
)


def process_status(config: SSHConfig, process_group: int) -> list[ProcessStatus]:
    ssh_cmd = _build_ssh_command(config, process_group)

    result = subprocess.run(
        ssh_cmd,
        shell=True,
        universal_newlines=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        encoding="utf-8",
    )

    return ProcessStatus.from_ps_output(result.stdout)


def _build_ssh_command(config: SSHConfig, process_group: int) -> str:
    ps_cmd = PS_CMD.format(process_group or "")
    return _SSH.format(
        port=config.port,
        keyfile=config.keyfile,
        user=config.user,
        host=config.host,
        ps_cmd=ps_cmd,
    )
