import re
import subprocess
from dataclasses import dataclass
from datetime import timedelta
from enum import Enum
from typing import cast

PS_CMD = "ps -g {} -o pid,state,%cpu,rss,cputime --no-headers"


class ProcessState(Enum):
    RUNNING = "R"
    SLEEPING = "S"
    STOPPED = "T"
    ZOMBIE = "Z"
    UNKNOWN = "?"

    def __str__(self) -> str:
        return self.name


@dataclass(frozen=True)
class ProcessStatus:
    pid: int
    state: ProcessState
    percent_cpu: float
    memory: int
    cpu_time: timedelta

    @classmethod
    def from_ps_output(cls, ps_output: str) -> list["ProcessStatus"]:
        def is_error(lines: list[str]) -> bool:
            return lines[0].startswith("error:")

        def parse_line(line: str) -> "ProcessStatus":
            pid, state, percent_cpu, memory, cpu_time, *_ = line.split()
            return cls(
                pid=int(pid),
                state=ProcessState(state[0]),
                percent_cpu=float(percent_cpu),
                memory=int(memory),
                cpu_time=timedelta(seconds=_cpu_time_to_seconds(cpu_time)),
            )

        lines = ps_output.strip().splitlines()
        if not lines or is_error(lines):
            return []

        return [parse_line(line) for line in lines]


def run(group: int) -> list[ProcessStatus]:
    cmd = PS_CMD.format(group)
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    return ProcessStatus.from_ps_output(result.stdout)


def _cpu_time_to_seconds(cpu_time: str) -> int:
    hours, minutes, seconds, *_ = cpu_time.split(":")
    return int(hours) * 3600 + int(minutes) * 60 + int(seconds)
