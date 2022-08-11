from flask import (
    Blueprint, flash, g, redirect, render_template, request, url_for
)
from werkzeug.exceptions import abort

bp = Blueprint('workflow', __name__)

@bp.route('/workflows/detail', methods=['GET'])
def detail():
    path = request.args.get('path')
    content = ''
    with open(path, 'r') as workflow:
        content += workflow.read()
    return render_template('workflows/detail.html', workflow=content)