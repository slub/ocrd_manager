import os

from pathlib import Path
from subprocess import Popen
from shutil import which

from flask import (
    Blueprint, redirect, render_template, current_app, request
)
from werkzeug.exceptions import abort

bp = Blueprint('workspace', __name__)

def get_workspace_paths():
    # recursively find METS file paths
    paths = []
    for mets in Path(current_app.config["BASEDIR"]).rglob('mets.xml'):
        if mets.match('.backup/*/mets.xml'):
            continue
        paths.append(str(mets))
    return paths

@bp.route('/workspaces/browse', methods=['GET'])
def browse():
    path = request.args.get('path')
    path = path.lstrip('/')
    path = os.path.join(current_app.config["BASEDIR"], path)
    
    if not os.path.exists(path):
        abort(404)
    else:
        
        if not path.endswith('mets.xml'):
            path = os.path.join(path, 'mets.xml')
        
        ## run app
        ret = Popen([which('browse-ocrd'),
                        '--display', ':' + str(current_app.config["BWPORT"] - 8080),
                        path])
        ## proxy does not work, because the follow-up requests would need to be forwarded, too:
        # response = urllib.request.urlopen('http://' + self.bwhost + ':' + str(self.bwport))
        # self.send_response(response.status)
        # for name, value in response.getheaders():
        #     self.send_header(name.rstrip(':'), value)
        # self.end_headers()
        # self.copyfile(response, self.wfile)
        ## so let's use temporary redirect instead
        return redirect("http://" + current_app.config["BWHOST"] + ":" + str(current_app.config["BWPORT"]))

@bp.route('/workspaces')
def index():
    relnames = []
    for path in get_workspace_paths():
        relnames.append(os.path.relpath(path, current_app.config["BASEDIR"]))
    return render_template('workspaces/index.html', relnames=relnames)
