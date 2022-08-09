from flask import (
    Blueprint, redirect, render_template, current_app
)

bp = Blueprint('index', __name__)

@bp.route('/')
def index():
    return render_template('index/index.html')

@bp.route('/logs')
def logs():
    return redirect("http://" + current_app.config["BWHOST"] + ":" + current_app.config["LOGPORT"])