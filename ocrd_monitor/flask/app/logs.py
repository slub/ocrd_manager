import os

from flask import (
    Blueprint, render_template, current_app, request
)
from werkzeug.exceptions import abort

bp = Blueprint('logs', __name__)

@bp.route('/logs/view', methods=['GET'])
def view():
    path = request.args.get('path')
    if not os.path.exists(path):
        abort(404)
    else:

        if not path.endswith('ocrd.log'):
            path = os.path.join(path, 'ocrd.log')

        content = []
        with open(path, 'r') as logs:
            content.extend(logs.readlines())
        return render_template('logs/view.html', logs=''.join(content))
