from dataclasses import replace
from datetime import timedelta
from pathlib import Path
from typing import Generator

import pytest
from bs4 import BeautifulSoup
from fastapi.templating import Jinja2Templates
from fastapi.testclient import TestClient
from httpx import Response
from ocrdmonitor.ocrdjob import OcrdJob
from ocrdmonitor.processstatus import ProcessState, ProcessStatus

from ocrdmonitor.server.app import TEMPLATE_DIR, create_app
from ocrdmonitor.server.jobs import ProcessQuery
from ocrdmonitor.server.settings import (
    OcrdBrowserSettings,
    OcrdControllerSettings,
    Settings,
)
from tests.ocrdmonitor.test_jobs import JOB_TEMPLATE, jobfile_content_for

job_dir = Path(__file__).parent / "ocrd.jobs"


@pytest.fixture(autouse=True)
def prepare_and_clean_files() -> Generator[None, None, None]:
    job_dir.mkdir(exist_ok=True)

    yield

    for jobfile in job_dir.glob("*"):
        jobfile.unlink()

    job_dir.rmdir()


def create_settings() -> Settings:
    return Settings(
        ocrd_browser=OcrdBrowserSettings(workspace_dir=Path(), port_range=(9000, 9100)),
        ocrd_controller=OcrdControllerSettings(job_dir=job_dir, host="", user=""),
    )


@pytest.mark.parametrize(
    argnames=["return_code", "result_text"],
    argvalues=[(0, "SUCCESS"), (1, "FAILURE")],
)
def test__given_a_completed_ocrd_job__the_job_endpoint_lists_it_in_a_table(
    return_code: int, result_text: str
) -> None:
    completed_job = replace(JOB_TEMPLATE, return_code=return_code)
    write_job_file_for(completed_job)
    settings = create_settings()
    sut = TestClient(create_app(settings))

    response = sut.get("/jobs/")

    assert response.is_success
    assert_lists_completed_job(completed_job, result_text, response)


def test__given_a_running_ocrd_job__the_job_endpoint_lists_it_with_resource_consumption(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    running_job, expected_status = create_running_ocrd_job(monkeypatch)
    sut = make_sut()

    response = sut.get("/jobs/")

    assert response.is_success
    assert_lists_running_job(running_job, expected_status, response)


def create_running_ocrd_job(
    monkeypatch: pytest.MonkeyPatch,
) -> tuple[OcrdJob, ProcessStatus]:
    pid = 1234
    expected_status = make_status(pid)
    running_job = replace(JOB_TEMPLATE, pid=pid)
    write_job_file_for(running_job)
    patch_process_query(monkeypatch, expected_status)
    return running_job, expected_status


def make_sut() -> TestClient:
    settings = create_settings()
    return TestClient(create_app(settings))


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
    table_id = "completed-jobs"
    soup = BeautifulSoup(response.content, "html.parser")
    texts = collect_texts_from_job_table(soup, table_id)

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
    table_id = "running-jobs"
    soup = BeautifulSoup(response.content, "html.parser")
    texts = collect_texts_from_job_table(soup, table_id)

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


def collect_texts_from_job_table(soup: BeautifulSoup, table_id: str) -> list[str]:
    cells_with_text = soup.select(f"#{table_id} td:not(:has(a)), #{table_id} td > a")
    texts = [r.text for r in cells_with_text]
    return texts


def write_job_file_for(completed_job: OcrdJob) -> None:
    content = jobfile_content_for(completed_job)
    jobfile = job_dir / "jobfile"
    jobfile.touch(exist_ok=True)
    jobfile.write_text(content)
