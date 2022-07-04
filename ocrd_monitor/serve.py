import os
import sys
import io
from datetime import datetime, timedelta
from functools import lru_cache
from pathlib import Path
from subprocess import Popen
from shutil import which
import html
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler
from socketserver import ForkingTCPServer
import subprocess
import urllib
from dotenv import dotenv_values
import click

class RequestHandler(SimpleHTTPRequestHandler):
    bwhost = "localhost"
    bwport = 8085
    logport = 8088
    basedir = "."

    def do_GET(self):
        # FIXME: HTTP auth # self.server.auth / self.checkAuthentication()
        self.bwhost = self.headers.get('Host').split(':')[0]
        # serve a listing of available workspaces with links to ocrd-browse them
        if self.path == '/':
            self._serve_index()
        elif self.path == '/jobs':
            self._serve_tasks()
        elif self.path == '/logs':
            self.send_response(HTTPStatus.SEE_OTHER) # or TEMPORARY_REDIRECT?
            self.send_header('Location', 'http://' + self.bwhost + ':' + str(self.logport))
            self.end_headers()
        elif self.path == '/data':
            self._serve_workspaces()
        elif self.path.startswith('/conf/'):
            path = self.path[6:].lstrip('/')
            path = urllib.parse.unquote(path)
            path = os.path.join(self.basedir, path)
            self._configure_workflow(path)
        # serve a single workspace
        elif self.path.startswith('/browse/'):
            path = self.path[7:].lstrip('/')
            path = urllib.parse.unquote(path)
            path = os.path.join(self.basedir, path)
            self._browse_workspace(path)
        elif self.path == '/reindex':
            self._workspaces.cache_clear()
            self.send_response(HTTPStatus.OK)
        else:
            #SimpleHTTPRequestHandler.do_GET(self)
            self.send_response(HTTPStatus.FORBIDDEN)

    def do_POST(self):
        self.do_GET()

    @property
    def _jobs(self):
        paths = []
        for jobfile in Path('/run/lock/ocrd.jobs').rglob('*'):
            paths.append(str(jobfile))
        return paths

    @property
    @lru_cache(maxsize=1)
    def _workspaces(self):
        # recursively find METS file paths
        paths = []
        for mets in Path(self.basedir).rglob('mets.xml'):
            if mets.match('.backup/*/mets.xml'):
                continue
            print(mets)
            paths.append(str(mets))
        return paths

    def _serve_index(self):
        # generate HTML with links
        enc = sys.getfilesystemencoding()
        title = 'OCR-D Monitor'
        r = []
        r.append('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" '
                 '"http://www.w3.org/TR/html4/strict.dtd">')
        r.append('<html>\n<head>')
        r.append('<meta http-equiv="Content-Type" '
                 'content="text/html; charset=%s">' % enc)
        r.append('<title>%s</title>\n</head>' % title)
        r.append('<body>\n<h1>%s</h1>' % title)
        r.append('<hr>\n\n')
        r.append('<h2><a href="/data">Show data</a></h2>\n')
        r.append('<h2><a href="/jobs">Show jobs</a></h2>\n')
        r.append('<h2><a href="/logs">Show logs</a></h2>\n')
        r.append('<hr>\n</body>\n</html>\n')
        # write to file
        encoded = '\n'.join(r).encode(enc, 'surrogateescape')
        f = io.BytesIO()
        f.write(encoded)
        f.seek(0)
        # send file
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-type", "text/html; charset=%s" % enc)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.copyfile(f, self.wfile)

    def _serve_tasks(self):
        # generate HTML with links
        # FIXME: live update via websockets etc
        # FIXME: show WORKDIR/ocrd.log via log-viewer endpoint
        enc = sys.getfilesystemencoding()
        title = 'OCR-D Tasks'
        r = []
        r.append('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" '
                 '"http://www.w3.org/TR/html4/strict.dtd">')
        r.append('<html>\n<head>')
        r.append('<meta http-equiv="Content-Type" '
                 'content="text/html; charset=%s">' % enc)
        r.append('<title>%s</title>\n</head>' % title)
        r.append('<body>\n<h1>%s</h1>' % title)
        r.append('<hr>\n<table>\n<tr>')
        r.append('<th>PID</th>\n'
                 '<th>STATUS</th>\n'
                 '<th>% CPU</th>\n'
                 '<th>MB RSS</th>\n'
                 '<th>DURATION</th>\n'
                 '<th>TASK ID</th>\n'
                 '<th>PROCESS ID</th>\n'
                 '<th>WORKSPACE</th>\n'
                 '<th>WORKFLOW</th></tr>\n')
        for pidfile in self._jobs:
            r.append('<tr>\n')
            job = dotenv_values(pidfile)
            remotedir = job['REMOTEDIR']
            workdir = job['WORKDIR']
            if workdir[0] != '/':
                workdir = os.path.join(self.basedir, workdir)
            workflow = job['WORKFLOW']
            if workflow[0] != '/':
                workflow = os.path.join(self.basedir, workflow)
            controller = os.environ['CONTROLLER']
            command = 'ssh -T -p %s ocrd@%s' % tuple(controller.split(':')[::-1])
            script = ('DIR=%s; test -e $DIR/ocrd.pid || exit 1\n'
                      'PID=`cat $DIR/ocrd.pid`\n'
                      'ps -g `ps -q $PID -o sid=` --forest -o pid,stat,pcpu,rss,cputime --no-headers' % remotedir)
            result = subprocess.run(command, input=script,
                                    shell=True, stdout=subprocess.PIPE,
                                    universal_newlines=True, encoding='utf-8')
            if result.returncode == 0 and result.stdout:
                pid = '?'
                status = '?'
                cpuutil = 0.0
                memrss = 0
                duration = timedelta()
                for result1 in result.stdout.split('\n'):
                    if not result1:
                        continue
                    pid1, status1, cpuutil1, memrss1, duration1 = result1.split()
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
            r.append('<td>%s</td>\n' % pid)
            r.append('<td>%s</td>\n' % status)
            r.append('<td>%s</td>\n' % cpuutil)
            r.append('<td>%s</td>\n' % memrss)
            r.append('<td>%s</td>\n' % duration)
            r.append('<td>%s</td>\n' % job['TASK_ID'])
            r.append('<td>%s</td>\n' % job['PROCESS_ID'])
            print(workdir)
            if os.path.exists(os.path.join(workdir, 'mets.xml')):
                r.append('<td><a href="/browse/%s">%s</a></td>'
                         % (urllib.parse.quote(os.path.relpath(workdir, self.basedir), errors='surrogatepass'),
                            html.escape(os.path.basename(job['PROCESS_DIR']), quote=False)))
            else:
                r.append('<td/>\n')
            print(workflow)
            if os.path.exists(workflow):
                r.append('<td><a href="/conf/%s">%s</a></td>\n'
                         % (urllib.parse.quote(os.path.relpath(workflow, self.basedir), errors='surrogatepass'),
                            html.escape(os.path.basename(workflow), quote=False)))
            else:
                r.append('<td>%s</td>\n' % os.path.basename(workflow))
        r.append('</table>\n<hr>\n</body>\n</html>\n')
        # write to file
        encoded = '\n'.join(r).encode(enc, 'surrogateescape')
        f = io.BytesIO()
        f.write(encoded)
        f.seek(0)
        # send file
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-type", "text/html; charset=%s" % enc)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.copyfile(f, self.wfile)

    def _configure_workflow(self, path):
        # generate HTML with links
        enc = sys.getfilesystemencoding()
        title = 'OCR-D Workflow Configuration'
        r = []
        r.append('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" '
                 '"http://www.w3.org/TR/html4/strict.dtd">')
        r.append('<html>\n<head>')
        r.append('<meta http-equiv="Content-Type" '
                 'content="text/html; charset=%s">' % enc)
        r.append('<title>%s</title>\n</head>' % title)
        r.append('<body>\n<h1>%s</h1>' % title)
        r.append('<hr>\n\n')
        r.append('<pre>\n')
        with open(path, 'r') as workflow:
            text = workflow.read()
            text = html.escape(text, quote=False)
            r.append(text)
        r.append('</pre>\n')
        r.append('<hr>\n</body>\n</html>\n')
        # write to file
        encoded = '\n'.join(r).encode(enc, 'surrogateescape')
        f = io.BytesIO()
        f.write(encoded)
        f.seek(0)
        # send file
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-type", "text/html; charset=%s" % enc)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.copyfile(f, self.wfile)

    def _serve_workspaces(self):
        # generate HTML with links
        enc = sys.getfilesystemencoding()
        basedir = os.path.realpath(self.basedir)
        title = html.escape(basedir, quote=False)
        title = 'OCR-D Browser for workspaces at %s' % title
        r = []
        r.append('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" '
                 '"http://www.w3.org/TR/html4/strict.dtd">')
        r.append('<html>\n<head>')
        r.append('<meta http-equiv="Content-Type" '
                 'content="text/html; charset=%s">' % enc)
        r.append('<title>%s</title>\n</head>' % title)
        r.append('<body>\n<h1>%s</h1>' % title)
        r.append('<hr>\n<ul>')
        for name in self._workspaces:
            relname = os.path.relpath(name, basedir)
            linkname = os.path.join('/browse', relname)
            r.append('<li><a href="%s">%s</a></li>'
                     % (urllib.parse.quote(linkname, errors='surrogatepass'),
                        html.escape(relname, quote=False)))
        r.append('</ul>\n<hr>\n</body>\n</html>\n')
        # write to file
        encoded = '\n'.join(r).encode(enc, 'surrogateescape')
        f = io.BytesIO()
        f.write(encoded)
        f.seek(0)
        # send file
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-type", "text/html; charset=%s" % enc)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.copyfile(f, self.wfile)

    def _browse_workspace(self, path):
        if not os.path.exists(path):
            self.send_response(HTTPStatus.NOT_FOUND)
        else:
            if not path.endswith('mets.xml'):
                path = os.path.join(path, 'mets.xml')
            ## run app
            ret = Popen([which('browse-ocrd'),
                         '--display', ':' + str(self.bwport - 8080),
                         path])
            ## proxy does not work, because the follow-up requests would need to be forwarded, too:
            # response = urllib.request.urlopen('http://' + self.bwhost + ':' + str(self.bwport))
            # self.send_response(response.status)
            # for name, value in response.getheaders():
            #     self.send_header(name.rstrip(':'), value)
            # self.end_headers()
            # self.copyfile(response, self.wfile)
            ## so let's use temporary redirect instead
            self.send_response(HTTPStatus.SEE_OTHER) # or TEMPORARY_REDIRECT?
            self.send_header('Location', 'http://' + self.bwhost + ':' + str(self.bwport))
            self.end_headers()

    # def log_message(self, format, *args):
    #     """ Override to prevent stdout on requests """
    #     pass

@click.command(context_settings={'help_option_names': ['-h', '--help']})
@click.option('-L', '--logport', default=8088, type=int, help="TCP port of Log viewer to delegate to")
@click.option('-P', '--bwport', default=8085, type=int, help="TCP port of Broadwayd to delegate to")
@click.option('-p', '--port', default=80, type=int, help="TCP port to bind the web server to")
@click.option('-l', '--listen', default="", type=str, help="network address to bind the web server to")
@click.option('-d', '--basedir', default=".", type=click.Path(exists=True, file_okay=False))
def cli(logport, bwport, port, listen, basedir):
    Handler = RequestHandler
    Handler.logport = logport
    Handler.bwport = bwport
    Handler.basedir = basedir
    ForkingTCPServer.allow_reuse_address = True
    with ForkingTCPServer((listen, port), Handler) as httpd:
        httpd.serve_forever()

if __name__ == '__main__':
    cli()
