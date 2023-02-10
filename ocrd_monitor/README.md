# OCRD-Monitor

The OCRD-Monitor application is used to monitor the progress and results of OCR-D jobs.
In order to run the application you need to have an OCR-D Controller as well as the Dozzle container for viewing logs set up.
To launch the monitor, first create a script containing the following code:

```bash
export OCRD_BROWSER__MODE=<native or docker>
export OCRD_BROWSER__WORKSPACE_DIR=<dir-containing-ocrd-workspaces>
export OCRD_BROWSER__PORT_RANGE="[9000,9100]"
export OCRD_CONTROLLER__JOB_DIR=<dir-containing-ocrd-job-files>
export OCRD_CONTROLLER__HOST=<url-to-ocrd-controller>
export OCRD_CONTROLLER__PORT=<port-of-ocrd-controller>
export OCRD_CONTROLLER__USER=<name-of-user-on-ocrd-controller>
export OCRD_CONTROLLER__KEYFILE=<path-to-private-ssh-key>
export OCRD_LOGVIEW__PORT=<port-of-dozzle>

cd ocrd_monitor
uvicorn "ocrdmonitor.main:app" --reload
```

Make sure to install the requirements from `requirements.txt`:

```bash
pip install -r requirements.txt
```

Finally launch the application using the script you created.
The OCRD-Monitor will be available at `http://localhost:8000`


## Testing

1. Install runtime and dev dependencies 
```bash
    pip install -r requirements.txt
    pip install -r requirements.dev.txt
```

2. Run nox or pytest
```bash
    nox
```

```bash
    pytest tests
```


## General overview

![](docs/img/monitor-overview.png)


## Overview of workspaces endpoint functionality

When opening a workspace OCR-D Monitor will launch a new `OcrdBrowser` instance (either as a Docker container or a sub process).
From there on it will proxy requests to the `/workspaces/view/<path>` endpoint to the browser instance.

![](docs/img/workspaces-endpoint.png)