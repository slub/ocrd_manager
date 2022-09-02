import os

from pathlib import Path
from subprocess import Popen
from shutil import which
from functools import lru_cache

from flask import (
    Blueprint, redirect, request, render_template, current_app, request
)
from werkzeug.exceptions import abort

bp = Blueprint('workspace', __name__)

@lru_cache(maxsize=1)
def get_workspace_paths():
    # recursively find METS file paths
    paths = []
    for mets in Path().rglob('mets.xml'):
        if mets.match('.backup/*/mets.xml'):
            continue
        paths.append(str(mets))
    return paths

@bp.route('/workspaces/browse', methods=['GET'])
def browse():
    path = request.args.get('path')
    if not os.path.exists(path):
        abort(404)
    else:

        if not path.endswith('mets.xml'):
            path = os.path.join(path, 'mets.xml')

        ## run app
        ret = Popen([which('browse-ocrd'),
                        '--display', ':' + str(int(current_app.config["BW_PORT"]) - 8080),
                        path])
        ## proxy does not work, because the follow-up requests would need to be forwarded, too:
        # response = urllib.request.urlopen('http://' + self.bwhost + ':' + str(self.bwport))
        # self.send_response(response.status)
        # for name, value in response.getheaders():
        #     self.send_header(name.rstrip(':'), value)
        # self.end_headers()
        # self.copyfile(response, self.wfile)
        ## so let's use temporary redirect instead
        return redirect("http://" + request.headers['Host'].split(':')[0] + ":" + current_app.config["BW_PORT"])

@bp.route('/workspaces')
def index():
    return render_template('workspaces/index.html', relnames=get_workspace_paths())

@bp.route('/workspaces/reindex')
def reindex():
    get_workspace_paths.cache_clear()
    return redirect('/workspaces')
