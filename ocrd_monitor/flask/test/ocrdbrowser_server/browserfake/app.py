import logging
from flask import Flask, render_template


def create_app(workspace: str) -> Flask:
    app = Flask(__name__)
    app.logger.level = logging.DEBUG

    @app.route("/")
    def index() -> str:
        app.logger.debug(workspace)
        return render_template("index.html.j2", workspace=workspace)

    return app
