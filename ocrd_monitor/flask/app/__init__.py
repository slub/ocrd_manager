import os

from flask import Flask

def create_app():
    # create and configure the app
    app = Flask(__name__, instance_relative_config=True)

    app.config.from_mapping(
        BASEDIR=os.getenv("APP_BASEDIR"),
        BW_PORT=os.getenv("APP_BW_PORT"),
        LOG_PORT=os.getenv("APP_LOG_PORT"),
    )

    # ensure the instance folder exists
    try:
        os.makedirs(app.instance_path)
    except OSError:
        pass

    from . import index
    app.register_blueprint(index.bp)
    app.add_url_rule('/', endpoint='index')

    from . import job
    app.register_blueprint(job.bp)

    from . import workflow
    app.register_blueprint(workflow.bp)

    from . import workspace
    app.register_blueprint(workspace.bp)

    return app
