from __future__ import annotations

from dataclasses import replace
from datetime import timedelta
from pathlib import Path
from typing import Generator

import pytest
from fastapi.testclient import TestClient
from httpx import Response
from ocrdmonitor.ocrdcontroller import ProcessQuery
from ocrdmonitor.ocrdjob import OcrdJob
from ocrdmonitor.processstatus import ProcessState, ProcessStatus
from ocrdmonitor.server.settings import OcrdControllerSettings
from tests.ocrdmonitor.server import scraping
from tests.ocrdmonitor.server.fixtures import JOB_DIR
from tests.ocrdmonitor.test_jobs import JOB_TEMPLATE, jobfile_content_for


@pytest.fixture(autouse=True)
def prepare_and_clean_files() -> Generator[None, None, None]:
    JOB_DIR.mkdir(exist_ok=True)

    yield

    for jobfile in JOB_DIR.glob("*"):
        jobfile.unlink()

    JOB_DIR.rmdir()


@pytest.fixture
def running_ocrd_job(
    monkeypatch: pytest.MonkeyPatch,
) -> Generator[tuple[OcrdJob, ProcessStatus], None, None]:
    pid = 1234
    expected_status = make_status(pid)
    running_job = replace(JOB_TEMPLATE, pid=pid)
    jobfile = write_job_file_for(running_job)
    patch_process_query(monkeypatch, expected_status)

    yield running_job, expected_status

    jobfile.unlink()


@pytest.mark.parametrize(
    argnames=["return_code", "result_text"],
    argvalues=[(0, "SUCCESS"), (1, "FAILURE")],
)
def test__given_a_completed_ocrd_job__the_job_endpoint_lists_it_in_a_table(
    app: TestClient,
    return_code: int,
    result_text: str,
) -> None:
    completed_job = replace(JOB_TEMPLATE, return_code=return_code)
    write_job_file_for(completed_job)

    response = app.get("/jobs/")

    assert response.is_success
    assert_lists_completed_job(completed_job, result_text, response)


def test__given_a_running_ocrd_job__the_job_endpoint_lists_it_with_resource_consumption(
    running_ocrd_job: tuple[OcrdJob, ProcessStatus],
    app: TestClient,
) -> None:
    job, expected_status = running_ocrd_job

    response = app.get("/jobs/")

    assert response.is_success
    assert_lists_running_job(job, expected_status, response)


def make_status(pid: int) -> ProcessStatus:
    expected_status = ProcessStatus(
        pid=pid,
        state=ProcessState.RUNNING,
        percent_cpu=0.25,
        memory=1024,
        cpu_time=timedelta(seconds=10, minutes=5, hours=1),
    )

    return expected_status


def patch_process_query(
    monkeypatch: pytest.MonkeyPatch, expected_status: ProcessStatus
) -> None:
    def make_process_query(self: OcrdControllerSettings) -> ProcessQuery:
        def process_query_stub(process_group: int) -> list[ProcessStatus]:
            if process_group != expected_status.pid:
                raise ValueError(f"Unexpected process group {process_group}")
            return [expected_status]

        return process_query_stub

    monkeypatch.setattr(OcrdControllerSettings, "process_query", make_process_query)


def assert_lists_completed_job(
    completed_job: OcrdJob, result_text: str, response: Response
) -> None:
    texts = collect_texts_from_job_table(response.content, "completed-jobs")

    assert texts == [
        str(completed_job.kitodo_details.task_id),
        str(completed_job.kitodo_details.process_id),
        completed_job.workflow_file.name,
        f"{completed_job.return_code} ({result_text})",
        completed_job.kitodo_details.processdir.name,
        "ocrd.log",
    ]


def assert_lists_running_job(
    running_job: OcrdJob,
    process_status: ProcessStatus,
    response: Response,
) -> None:
    texts = collect_texts_from_job_table(response.content, "running-jobs")

    assert texts == [
        str(running_job.kitodo_details.task_id),
        str(running_job.kitodo_details.process_id),
        running_job.workflow_file.name,
        str(process_status.pid),
        str(process_status.state),
        str(process_status.percent_cpu),
        str(process_status.memory),
        str(process_status.cpu_time),
    ]


def collect_texts_from_job_table(content: bytes, table_id: str) -> list[str]:
    selector = f"#{table_id} td:not(:has(a)), #{table_id} td > a"
    return scraping.parse_texts(content, selector)


def write_job_file_for(job: OcrdJob) -> Path:
    content = jobfile_content_for(job)
    jobfile = JOB_DIR / "jobfile"
    jobfile.touch(exist_ok=True)
    jobfile.write_text(content)
    return jobfile
