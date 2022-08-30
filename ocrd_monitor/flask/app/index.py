from flask import (
    Blueprint, redirect, render_template, current_app, request
)

bp = Blueprint('index', __name__)

@bp.route('/')
def index():
    return render_template('index/index.html')

@bp.route('/logs')
def logs():
    return redirect("http://" + request.headers['Host'].split(':')[0] + ":" + current_app.config["LOG_PORT"])
