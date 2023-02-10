import sys
from pathlib import Path
from typing import Protocol

from ocrdmonitor.ocrdjob import OcrdJob
from ocrdmonitor.processstatus import ProcessStatus

if sys.version_info >= (3, 10):
    from typing import TypeGuard
else:
    from typing_extensions import TypeGuard


class ProcessQuery(Protocol):
    def __call__(self, process_group: int) -> list[ProcessStatus]:
        ...


class OcrdController:
    def __init__(self, process_query: ProcessQuery, job_dir: Path) -> None:
        self._process_query = process_query
        self._job_dir = job_dir

    def get_jobs(self) -> list[OcrdJob]:
        def is_ocrd_job(j: OcrdJob | None) -> TypeGuard[OcrdJob]:
            return j is not None

        job_candidates = [
            self._try_parse(job_file.read_text())
            for job_file in self._job_dir.iterdir()
            if job_file.is_file()
        ]

        return list(filter(is_ocrd_job, job_candidates))

    def _try_parse(self, job_str: str) -> OcrdJob | None:
        try:
            return OcrdJob.from_str(job_str)
        except (ValueError, KeyError):
            return None

    def status_for(self, ocrd_job: OcrdJob) -> ProcessStatus | None:
        if ocrd_job.pid is None:
            return None

        process_statuses = self._process_query(ocrd_job.pid)
        matching_statuses = (
            status for status in process_statuses if status.pid == ocrd_job.pid
        )
        return next(matching_statuses, None)
