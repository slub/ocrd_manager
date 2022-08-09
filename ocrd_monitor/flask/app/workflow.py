from flask import (
    Blueprint, flash, g, redirect, render_template, request, url_for
)
from werkzeug.exceptions import abort

from app.auth import login_required
from app.db import get_db

bp = Blueprint('workflow', __name__)

@bp.route('/workflows/configure')
def configure():
    path = ''
    content = ''
    with open(path, 'r') as workflow:
        content += workflow.read()
    return render_template('workflow/configure.html', workflowContent=content)