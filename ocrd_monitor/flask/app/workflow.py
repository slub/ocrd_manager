import os
from flask import (
    Blueprint, flash, g, redirect, render_template, request, current_app, url_for
)
from werkzeug.exceptions import abort

bp = Blueprint('workflow', __name__)

@bp.route('/workflows/detail', methods=['GET'])
def detail():
    path = request.args.get('path')
    path = path.lstrip('/')
    path = os.path.join(current_app.config["BASEDIR"], path)
    current_app.logger.info(os.path.isfile(path))
    if not os.path.exists(path) or os.path.isdir(path):
        abort(404)
    else:    
        content = ''
        with open(path, 'r') as workflow:
            content += workflow.read()
        return render_template('workflows/detail.html', workflow=content)
