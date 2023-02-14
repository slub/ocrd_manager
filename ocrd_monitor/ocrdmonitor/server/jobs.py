from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from fastapi import APIRouter, Request, Response
from fastapi.templating import Jinja2Templates

from ocrdmonitor.ocrdcontroller import OcrdController
from ocrdmonitor.ocrdjob import OcrdJob
from ocrdmonitor.processstatus import ProcessStatus


@dataclass
class RunningJob:
    ocrd_job: OcrdJob
    process_status: ProcessStatus


def split_into_running_and_completed(
    jobs: Iterable[OcrdJob],
) -> tuple[list[OcrdJob], list[OcrdJob]]:
    running_ocrd_jobs = [job for job in jobs if job.is_running]
    completed_ocrd_jobs = [job for job in jobs if job.is_completed]
    return running_ocrd_jobs, completed_ocrd_jobs


def wrap_in_running_job_type(
    running_ocrd_jobs: Iterable[OcrdJob],
    job_status: Iterable[ProcessStatus | None],
) -> Iterable[RunningJob]:
    running_jobs = [
        RunningJob(job, process_status)
        for job, process_status in zip(running_ocrd_jobs, job_status)
        if process_status is not None
    ]

    return running_jobs


def create_jobs(templates: Jinja2Templates, controller: OcrdController) -> APIRouter:
    router = APIRouter(prefix="/jobs")

    @router.get("/", name="jobs")
    def jobs(request: Request) -> Response:
        jobs = controller.get_jobs()
        running, completed = split_into_running_and_completed(jobs)

        job_status = [controller.status_for(job) for job in running]
        running_jobs = wrap_in_running_job_type(running, job_status)

        return templates.TemplateResponse(
            "jobs.html.j2",
            {
                "request": request,
                "running_jobs": running_jobs,
                "completed_jobs": completed,
            },
        )

    return router
