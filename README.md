# OCR-D Manager

OCR-D Manager is a server that mediates between [Kitodo](https://github.com/kitodo) and [OCR-D](https://ocr-d.de). It resides on the site of the Kitodo installation (so the actual OCR server can be managed independently) but runs in its own container (so Kitodo can be managed independently).

Specifically, it gets called by [Kitodo.Production](https://github.com/kitodo/kitodo-production) or [Kitodo.Presentation](https://github.com/kitodo-presentation) to handle OCR for a document, and in turn calls the [OCR-D Controller](https://github.com/bertsky/ocrd_controller) for workflow processing.

For an integration as a **service container**, orchestrated with other containers (Kitodo+Controller), see [this meta-repo](https://github.com/markusweigelt/kitodo_production_ocrd).

OCR-D Manager is responsible for
- data transfer from Kitodo to Manager to Controller and back,
- delegation to Controller,
- signalling/reporting,
- result validation,
- result extraction (putting ALTO files in the process directory where Kitodo.Production expects them, or updating the METS for Kitodo.Presentation).

It is currently implemented as SSH login server with an installation of [OCR-D core](https://github.com/OCR-D/core) and an SSH client to connect to the Controller.

 * [Usage](#usage)
   * [Building](#building)
   * [Starting and mounting](#starting-and-mounting)
   * [General management](#general-management)
   * [Processing](#processing)
     * [From image to ALTO files](#from-image-to-alto-files)
     * [From METS to METS file](#from-mets-to-mets-file)
   * [Data transfer](#data-transfer)
   * [Logging](#logging)
   * [Monitoring](#monitoring)
 * [Testing](#testing)

## Usage

### Building

Build or pull the Docker image:

    make build # or docker pull markusweigelt/ocrd_manager

### Starting and mounting

Then run the container – providing a **host-side directory** for the volume …

 * `DATA`: directory for data processing (including images or existing workspaces),  
   defaults to current working directory

… but also files …

 * `KEYS`: public key **credentials** for log-in to the manager
 * `PRIVATE`: private key **credentials** for log-in to the controller …
 
… and (optionally) some **environment variables** …

 * `UID`: numerical user identifier to be used by programs in the container  
    (will affect the files modified/created); defaults to current user
 * `GID`: numerical group identifier to be used by programs in the container  
    (will affect the files modified/created); defaults to current group
 * `UMASK`: numerical user mask to be used by programs in the container  
    (will affect the files modified/created); defaults to 0002
 * `PORT`: numerical TCP port to expose the SSH server on the host side  
    defaults to 9022 (for non-priviledged access)
 * `CONTROLLER` network address:port for the controller client
			(must be reachable from the container network)
 * `ACTIVEMQ` network address:port of ActiveMQ server listening to result status
			(must be reachable from the container network)
 * `NETWORK` name of the Docker network to use  
    defaults to `bridge` (the default Docker network)

… thus, for **example**:

    make run DATA=/mnt/workspaces MODELS=~/.local/share KEYS=~/.ssh/id_rsa.pub PORT=9022 PRIVATE=~/.ssh/id_rsa

(You can also run the service via `docker-compose` manually – just `cp .env.example .env` and edit to your needs.)

### General management

Then you can **log in** as user `ocrd` from remote (but let's use `manager` in the following – 
without loss of generality):

    ssh -p 9022 ocrd@manager bash -i

(Typically though, you will run a non-interactive script, see next section.)

### Processing

In the Manager, you can run shell scripts that do
- data management and validation via `ocrd` CLIs
- OCR processing by running workflows in the controller via `ssh ocrd@ocrd_controller` log-ins

The data management will depend on which Kitodo context you want to integrate into (Production 2 / 3 or Presentation).

#### From image to ALTO files

For **Kitodo.Production**, there is a preconfigured script `for_production.sh` which takes the following arguments:

```sh
SYNOPSIS:

for_production.sh [OPTIONS] DIRECTORY

where OPTIONS can be any/all of:
 --lang LANGUAGE    overall language of the material to process via OCR
 --script SCRIPT    overall script of the material to process via OCR
 --workflow FILE    workflow file to use for processing, default:
                    ocr-workflow-default.sh
 --img-subdir IMG   name of the subdirectory to read images from, default:
                    images
 --ocr-subdir OCR   name of the subdirectory to write OCR results to, default:
                    ocr/alto
 --proc-id ID       process ID to communicate in ActiveMQ callback
 --task-id ID       task ID to communicate in ActiveMQ callback
 --help             show this message and exit

and DIRECTORY is the local path to process. The script will import
the images from DIRECTORY/IMG into a new (temporary) METS and
transfer this to the Controller for processing. After resyncing back
to the Manager, it will then extract OCR results and export them to
DIRECTORY/OCR.

If ActiveMQ is used, the script will exit directly after initialization,
and run processing in the background. Completion will then be signalled
via ActiveMQ network protocol (using the proc and task ID as message).

ENVIRONMENT VARIABLES:

 CONTROLLER: host name and port of OCR-D Controller for processing
 ACTIVEMQ: URL of ActiveMQ server for result callback (optional)
 ACTIVEMQ_CLIENT: path to ActiveMQ client library JAR file (optional)
```

The `workflow` parameter is optional and defaults to the preconfigured script `ocr-workflow-default.sh`
which contains a trivial workflow:
- import of the images into a new OCR-D workspace
- preprocessing, layout analysis and text recognition with a single Tesseract processor call
- format conversion of the result from PAGE-XML to ALTO-XML

It can be replaced with the (path) name of any workflow script mounted under `/data`.

For example (assuming `testdata` is a directory with image files mounted under `/data`):

    ssh -T -p 9022 ocrd@manager for_production.sh --proc-id 1 --task-id 3 --lang deu --script Fraktur --workflow myocr.sh testdata


#### From METS to METS file

For **Kitodo.Presentation**, there is a preconfigured script `for_presentation.sh` which takes the following arguments:

```sh
SYNOPSIS:

for_presentation.sh [OPTIONS] METS

where OPTIONS can be any/all of:
 --workflow FILE    workflow file to use for processing, default:
                    ocr-workflow-default.sh
 --pages RANGE      selection of physical page range to process
 --img-grp GRP      fileGrp to read input images from, default:
                    DEFAULT
 --ocr-grp GRP      fileGrp to write output OCR text to, default:
                    FULLTEXT
 --url-prefix URL   convert result text file refs from local to URL
                    and prefix them
 --help             show this message and exit

and METS is the path of the METS file to process. The script will copy
the METS into a new (temporary) workspace and transfer this to the
Controller for processing. After resyncing back, it will then extract
OCR results and copy them to METS (adding file references to the file
and copying files to the parent directory).

ENVIRONMENT VARIABLES:

 CONTROLLER: host name and port of OCR-D Controller for processing
```

The same goes here for the `workflow parameter`.

For example (assuming `testdata` is a directory with image files mounted under `/data`):

    ssh -T -p 9022 ocrd@manager for_presentation.sh --lang deu --script Fraktur --workflow myocr.sh testdata/mets.xml


### Data transfer

For sharing data between the Manager and Controller, it is recommended to transfer files _explicitly_
(as this will make the costs more measurable and controllable).

(This is currently implemented via `rsync`.)

The data lifecycle should be:
- on Controller: short-lived
- on Manager: as long as process is active in Production

(This is currently not managed.)

### Logging

All logs are accumulated on standard output, which can be inspected via Docker:

    docker logs ocrd_manager

### Monitoring

The repo also provides a web server featuring
- (intermediate) results for all current document workspaces (via [OCR-D Browser](https://github.com/hnesk/browse-ocrd))
- a log viewer
- a job viewer
- :construction: workflow editor

Build or pull the Docker image:

    make build-monitor # or docker pull bertsky/ocrd_monitor

Then run the container – providing the same variables as above:

    make run-monitor DATA=/mnt/workspaces

You can then open `http://localhost:8080` in your browser.

## Testing

After [building](#building) and [starting](#starting-and-mounting), you can use the `test` target
for a round-trip:

    make test DATA=/mnt/workspaces

This will download sample data and run the default workflow on them.

(If the Manager has been started externally already, make sure to pass the correct value
 for the `NETWORK` variable – the makefile will then attempt to use `docker exec` instead of
 `ssh ocrd@localhost` to connect.)
