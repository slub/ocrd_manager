from typing import Set, Tuple, Dict
import atexit
import uuid
from os import path

from werkzeug.exceptions import abort

import ocrdbrowser
from flask import Blueprint, flash, render_template, request, session
from ocrdbrowser import (
    NoPortsAvailableError,
    OcrdBrowser,
    OcrdBrowserFactory,
    workspace,
)

def create_blueprint(
    process_factory: OcrdBrowserFactory, workspace_dir: str
) -> Blueprint:
    running_browsers: Set[OcrdBrowser] = set()

    bp = Blueprint("workspaces", __name__, url_prefix="/workspaces")

    @bp.route("/")
    def index() -> str:
        workspaces = workspace.list_all(workspace_dir)
        return render_template("workspaces/index.html.j2", workspaces=workspaces)

    @bp.route("/<path:workspace>")
    def view_workspace(workspace: str) -> str:
        session_id = session.setdefault("id", str(uuid.uuid4()))
        full_path = path.join(workspace_dir, workspace)
        host=""
        port=""
        if not ocrdbrowser.workspace.is_valid(full_path):
            flash("Not a valid workspace", category="error")
        else:
            stop_owned_browsers_in_other_workspaces(session_id, full_path)
            port = try_launch_browser(session_id, full_path)
            host = request.headers['Host'].split(':')[0]

        return render_template("workspaces/view_workspace.html.j2", host=host, port=port, session_id=session_id)

    @bp.route("/check-browser-availability/<int:port>")
    def check_port(port) -> Tuple[Dict[str, str], int]:
        session_id = request.args.get('sessionId')
        own_browsers = ocrdbrowser.filter_owned(session_id, running_browsers)
        for browser in own_browsers:
            if browser.address() == str(port):
                return {"msg": "Browser is available"}, 200

        abort(404)

    def stop_owned_browsers_in_other_workspaces(
        session_id: str, full_path: str
    ) -> None:
        own_browsers = ocrdbrowser.filter_owned(session_id, running_browsers)
        in_other_workspaces = ocrdbrowser.in_other_workspaces(full_path, own_browsers)
        ocrdbrowser.stop_all(in_other_workspaces)

    def try_launch_browser(session_id: str, full_path: str) -> str:
        address = ""
        try:
            browser = ocrdbrowser.launch(
                full_path, session_id, process_factory, running_browsers
            )
            running_browsers.add(browser)
            address = browser.address()
        except NoPortsAvailableError:
            flash("Not enough resources to open the workspace", category="error")

        return address

    atexit.register(ocrdbrowser.stop_all, running_browsers)

    return bp
