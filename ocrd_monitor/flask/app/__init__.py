import os
from typing import Optional, TypeVar
import uuid

from flask import Flask
from ocrdbrowser import OcrdBrowserFactory, SubProcessOcrdBrowserFactory


def create_app(
    browser_factory: Optional[OcrdBrowserFactory] = None,
    workspace_dir: Optional[str] = None,
) -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    app.secret_key = str(uuid.uuid4())
    app.config.from_mapping(
        BW_PORT=os.getenv("APP_BW_PORT"),
        LOG_PORT=os.getenv("APP_LOG_PORT"),
    )

    os.makedirs(app.instance_path, exist_ok=True)

    from . import index

    app.register_blueprint(index.bp)
    app.add_url_rule("/", endpoint="index")

    from . import job

    app.register_blueprint(job.bp)

    from . import workflow

    app.register_blueprint(workflow.bp)

    from . import workspaces

    browser_factory = get_or_default(
        browser_factory,
        SubProcessOcrdBrowserFactory(
            host="http://0.0.0.0",
            available_ports=set(range(8500, 8601)),
        ),
    )

    workspace_dir = get_or_default(workspace_dir, ".backup")
    app.register_blueprint(workspaces.create_blueprint(browser_factory, workspace_dir))

    from . import logs

    app.register_blueprint(logs.bp)

    return app


T = TypeVar("T")


def get_or_default(value: Optional[T], default: T) -> T:
    return value if value is not None else default
