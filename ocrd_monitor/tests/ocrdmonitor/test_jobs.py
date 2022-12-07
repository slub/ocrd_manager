from dataclasses import replace
from pathlib import Path


from ocrdmonitor.ocrdjob import OcrdJob, KitodoProcessDetails


JOB_PID_LINE = "PID={pid}\n"
JOB_RETURN_CODE_LINE = "RETVAL={return_code}\n"

JOB_FILE_TEMPLATE = """
PROCESS_ID={kitodo_process_id}
TASK_ID={kitodo_task_id}
PROCESS_DIR={kitodo_process_dir}
WORKDIR={workdir}
REMOTEDIR={remotedir}
WORKFLOW={workflow}
CONTROLLER={controller_address}
"""


JOB_TEMPLATE = OcrdJob(
    kitodo_details=KitodoProcessDetails(
        process_id=5432,
        task_id=45989,
        processdir=Path("/data/5432"),
    ),
    workdir=Path("ocr-d/data/5432"),
    workflow_file=Path("ocr-workflow-default.sh"),
    remotedir="/remote/job/dir",
    controller_address="controller.ocrdhost.com",
)


def jobfile_content_for(job: OcrdJob) -> str:
    out = JOB_FILE_TEMPLATE.format(
        kitodo_process_id=job.kitodo_details.process_id,
        kitodo_task_id=job.kitodo_details.task_id,
        kitodo_process_dir=job.kitodo_details.processdir.as_posix(),
        workdir=job.workdir.as_posix(),
        workflow=job.workflow_file.as_posix(),
        remotedir=job.remotedir,
        controller_address=job.controller_address,
    )

    if job.pid is not None:
        out = JOB_PID_LINE.format(pid=job.pid) + out

    if job.return_code is not None:
        out = JOB_RETURN_CODE_LINE.format(return_code=job.return_code) + out

    return out


def test__parsing_a_ocrd_job_file_for_completed_job__returns_ocrdjob_with_a_return_code() -> None:
    expected = replace(JOB_TEMPLATE, return_code=0)
    content = jobfile_content_for(expected)

    actual = OcrdJob.from_str(content)

    assert actual == expected


def test__parsing_a_ocrd_job_file_for_running_job__returns_ocrdjob_with_a_process_id() -> None:
    expected = replace(JOB_TEMPLATE, pid=1)
    content = jobfile_content_for(expected)

    actual = OcrdJob.from_str(content)

    assert actual == expected
