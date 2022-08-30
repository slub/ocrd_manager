import os
import subprocess

import sys

from datetime import datetime, timedelta
from pathlib import Path

from dotenv import dotenv_values

from flask import (
    Blueprint, render_template, current_app
)

bp = Blueprint('job', __name__)

def get_resource_consumption(remotedir):
    script = ('DIR=%s; test -e $DIR/ocrd.pid || exit 1\n'
                    'PID=`cat $DIR/ocrd.pid`\n'
                    #'PID=`ps -q "$PID" -o sid=` || exit 2\n'
                    'ps -g "$PID" --forest -o pid,stat,pcpu,rss,cputime --no-headers' % remotedir)
    controller = os.environ['CONTROLLER']
    command = 'ssh -T -p %s admin@%s' % tuple(controller.split(':')[::-1])                
    result = subprocess.run(command, input=script,
                    shell=True, stdout=subprocess.PIPE,
                    universal_newlines=True, encoding='utf-8')
    if result.returncode == 0 and result.stdout:
        pid = '?'
        status = '?'
        cpuutil = 0.0
        memrss = 0
        duration = timedelta()
        for line in result.stdout.split('\n'):
            if not line:
                continue
            pid1, status1, cpuutil1, memrss1, duration1 = line.split()
            if status1[0] in 'DS':
                status1 = 'sleeping'
            elif status1[0] in 'Tt':
                status1 = 'stopped'
            elif status1[0] in 'XZ':
                status1 = 'zombie'
            else:
                status1 = 'running'
            cpuutil1 = float(cpuutil1)
            memrss1 = int(memrss1)//1024
            duration1 = datetime.strptime(duration1, '%H:%M:%S')
            duration1 = timedelta(hours=duration1.hour, minutes=duration1.minute, seconds=duration1.second)
            if status1 == 'running':
                status = 'running'
                pid = pid1
            elif status == '?':
                status = status1
            cpuutil += cpuutil1
            memrss += memrss1
            duration += duration1
        cpuutil = str(cpuutil)
        memrss = str(memrss)
        duration = str(duration)
    else:
        pid, status, cpuutil, memrss, duration = '?', 'terminated', '?', '?', '??:??:??'

    return pid, status, cpuutil, memrss, duration                    

def get_jobs():
    jobs = []
    for jobfile in Path('/run/lock/ocrd.jobs').rglob('*'):
        jobfile_values = dotenv_values(jobfile)

        remotedir = jobfile_values['REMOTEDIR']
        workdir = jobfile_values['WORKDIR']
        if workdir[0] != '/':
            workdir = os.path.join(current_app.config["BASEDIR"], workdir)
        workflow = jobfile_values['WORKFLOW']
        if workflow[0] != '/':
            workflow = os.path.join(current_app.config["BASEDIR"], workflow)
        job = {
            "task": {
                "id" : jobfile_values['TASK_ID']
            },
            "process": {
                "id" : jobfile_values['PROCESS_ID']
            }, 
           "resource_consumption": get_resource_consumption(remotedir)
        }

        workspace = os.path.join(workdir, 'mets.xml')
        if os.path.exists(workspace):
            job["workspace"] = {
                "name" : os.path.basename(workspace),
                "path" : os.path.relpath(workspace, current_app.config["BASEDIR"])
            }

        if os.path.exists(workflow) :
            job["workflow"] = {
                "name" : os.path.basename(workflow),
                "path" : os.path.relpath(workflow, current_app.config["BASEDIR"])
            }

        jobs.append(job)
    return jobs

@bp.route('/jobs')
def index():
    return render_template('jobs/index.html', jobs=get_jobs())
