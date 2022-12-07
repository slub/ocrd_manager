import datetime

import pytest
from ocrdmonitor.processstatus import ProcessState, ProcessStatus, run

PS_OUTPUT = """
        1  Ss   0.0  3872 01:12:46
        20 R+  49.7  1556 02:33:02
"""

INVALID_GROUP_OUTPUT = (
    "error: list of session leaders OR effective group names must follow -g"
)
INVALID_FORMAT_OUTPUT = "error: unknown user-defined format specifier"
FAILING_OUTPUTS = ["", INVALID_GROUP_OUTPUT, INVALID_FORMAT_OUTPUT]


def test__parsing_psoutput__returns_list_of_process_status() -> None:
    actual = ProcessStatus.from_ps_output(PS_OUTPUT)

    assert actual == [
        ProcessStatus(
            pid=1,
            state=ProcessState.SLEEPING,
            percent_cpu=0.0,
            memory=3872,
            cpu_time=datetime.timedelta(hours=1, minutes=12, seconds=46),
        ),
        ProcessStatus(
            pid=20,
            state=ProcessState.RUNNING,
            percent_cpu=49.7,
            memory=1556,
            cpu_time=datetime.timedelta(hours=2, minutes=33, seconds=2),
        ),
    ]


@pytest.mark.parametrize("output", FAILING_OUTPUTS)
def test__parsing_psoutput_with_error__returns_empty_list(output: str) -> None:
    actual = ProcessStatus.from_ps_output(output)

    assert actual == []
