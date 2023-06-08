#!/bin/bash
# OCR-D task to be run as OCR script step by Kitodo.Production
# To be called (after copying images to directory) via Manager, e.g.:
#     ssh -Tn -p 9022 ocrd@ocrd-manager process_images.sh \
#                                       --lang deu --script Fraktur \
#                                       --img-subdir images --ocr-subdir ocr/alto \
#                                       --task-id 501543 --proc-id 3 \
#                                       /home/goobi/work/daten/501543
# full CLI options: see --help

set -Eeu
set -o pipefail

parse_args() {
  LANGUAGE=
  SCRIPT=
  PROCESS_ID=
  TASK_ID=
  WORKFLOW=/workflows/ocr-workflow-default.sh
  IMAGES_SUBDIR=images
  RESULT_SUBDIR=ocr/alto
  while (($#)); do
    case "$1" in
      --help|-h) cat <<EOF
SYNOPSIS:

$0 [OPTIONS] DIRECTORY

where OPTIONS can be any/all of:
 --lang LANGUAGE    overall language of the material to process via OCR
 --script SCRIPT    overall script of the material to process via OCR
 --workflow FILE    workflow file to use for processing, default:
                    $WORKFLOW
 --img-subdir IMG   name of the subdirectory to read images from, default:
                    $IMAGES_SUBDIR
 --ocr-subdir OCR   name of the subdirectory to write OCR results to, default:
                    $RESULT_SUBDIR
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
 ACTIVEMQ_QUEUE: Protocol type handling result callbacks. Choose between "FinalizeTaskQueue" (default) or "TaskActionQueue" (optional)
 ACTIVEMQ_CLIENT: path to ActiveMQ client library JAR file (optional)
EOF
                 exit;;
      --lang) LANGUAGE="$2"; shift;;
      --script) SCRIPT="$2"; shift;;
      --workflow) WORKFLOW="$2"; shift;;
      --img-subdir) IMAGES_SUBDIR="$2"; shift;;
      --ocr-subdir) RESULT_SUBDIR="$2"; shift;;
      --proc-id) PROCESS_ID="$2"; shift;;
      --task-id) TASK_ID="$2"; shift;;
      *) PROCESS_DIR="$1";
         break;;
    esac
    shift
  done
  if (($#>1)); then
    logger -p user.error -t $TASK "invalid extra arguments $*"
    exit 1
  fi
}

source ocrd_lib.sh

init "$@"

# run the workflow script on the Controller non-interactively and log its output locally
# subsequently validate and postprocess the results
# do all this in a subshell in the background, so we can return immediately
(
  init_task

  pre_process_to_workdir

  pre_sync_workdir

  kitodo_production_task_action_process

  ocrd_exec ocrd_import_workdir ocrd_validate_workflow ocrd_process_workflow

  post_sync_workdir

  post_validate_workdir

  post_process_to_procdir

  kitodo_production_task_action_close

) |& tee -a $WORKDIR/ocrd.log 2>&1 | logger -p user.info -t $TASK &>/dev/null & # without output redirect, ssh will not close the connection upon exit, cf. #9

close
