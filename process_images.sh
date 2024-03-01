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
  VALIDATE=1
  IMAGES_SUBDIR=images
  RESULT_SUBDIR=ocr/alto
  ASYNC=false
  WEBHOOK_RECEIVER_URL=
  ACTIVEMQ_QUEUE=FinalizeTaskQueue
  while (($#)); do
    case "$1" in
      --help|-h) cat <<EOF
SYNOPSIS:

$0 [OPTIONS] DIRECTORY

where OPTIONS can be any/all of:
 --lang LANGUAGE          overall language of the material to process via OCR
 --script SCRIPT          overall script of the material to process via OCR
 --workflow FILE          workflow file to use for processing, default:
                          $WORKFLOW
 --no-validate            skip comprehensive validation of workflow results
 --img-subdir IMG         name of the subdirectory to read images from, default:
                          $IMAGES_SUBDIR
 --ocr-subdir OCR         name of the subdirectory to write OCR results to, default:
                          $RESULT_SUBDIR
 --proc-id ID             process ID for the assignment to the process folder
 --task-id ID             task ID to communicate in ActiveMQ
 --async                  run asynchronously (i.e. exit after init, but keep processing in background)
 --activemq-url           URL of ActiveMQ server for result callback
 --activemq-queue         protocol type of ActiveMQ server (FinalizeTaskQueue|TaskActionQueue), default:
                          $ACTIVEMQ_QUEUE
 --help                   show this message and exit

and DIRECTORY is the local path to process. The script will import
the images from DIRECTORY/IMG into a new (temporary) METS and
transfer this to the Controller for processing. After resyncing back
to the Manager, it will then extract OCR results and export them to
DIRECTORY/OCR.

ENVIRONMENT VARIABLES:

 CONTROLLER: host name and port of OCR-D Controller for processing

EOF
                 exit;;
      --lang) LANGUAGE="$2"; shift;;
      --script) SCRIPT="$2"; shift;;
      --workflow) WORKFLOW="$2"; shift;;
      --no-validate) VALIDATE=0;;
      --img-subdir) IMAGES_SUBDIR="$2"; shift;;
      --ocr-subdir) RESULT_SUBDIR="$2"; shift;;
      --proc-id) PROCESS_ID="$2"; shift;;
      --task-id) TASK_ID="$2"; shift;;
      --async) ASYNC=true;;
      --activemq-url) WEBHOOK_RECEIVER_URL="$2"; shift;;
      --activemq-queue) ACTIVEMQ_QUEUE="$2"; shift;;
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

# Key data to identifiy related entity in the receiver system
WEBHOOK_KEY_DATA=$TASK_ID

# Overwrite webhook_request "$WEBHOOK_RECEIVER_URL" "$WEBHOOK_KEY_DATA" "$EVENT" "$MESSAGE"
webhook_request() {
  ACTION=""

  case "$3" in
    INFO)
      ACTION="COMMENT"
      ;;
    ERROR)
      ACTION="ERROR_OPEN"
      ;;
    STARTED)
      ACTION="PROCESS"
      ;;
    COMPLETED)
      ACTION="CLOSE"
      ;;      
    *)
      logger -p user.error -t $TASK "Unknown task action type"
      ;;
  esac
  
  if test -n "$ACTION"; then
    if test "$ACTIVEMQ_QUEUE" == "TaskActionQueue"; then
      java -Dlog4j2.configurationFile=$KITODO_PRODUCTION_ACTIVEMQ_CLIENT_LOG4J2 -jar "$KITODO_PRODUCTION_ACTIVEMQ_CLIENT" "${1}" "$ACTIVEMQ_QUEUE" ${2} "${4}" "$ACTION"
    elif test "$ACTION" == "CLOSE"; then
      java -Dlog4j2.configurationFile=$KITODO_PRODUCTION_ACTIVEMQ_CLIENT_LOG4J2 -jar "$KITODO_PRODUCTION_ACTIVEMQ_CLIENT" "${1}" "$ACTIVEMQ_QUEUE" ${2} "${4}"
    fi
  fi
}

# run the workflow script on the Controller non-interactively and log its output locally
# subsequently validate and postprocess the results
# do all this in a subshell in the background, so we can return immediately
(
  init_task

  pre_process_to_workdir

  pre_sync_workdir

  webhook_send_started

  ocrd_exec ocrd_import_workdir ocrd_validate_workflow ocrd_process_workflow

  post_sync_workdir

  if ((VALIDATE)); then post_validate_workdir; fi

  post_process_to_procdir

  webhook_send_completed

) |& tee -a $WORKDIR/ocrd.log 2>&1 | logger -p user.info -t $TASK &>/dev/null & # without output redirect, ssh will not close the connection upon exit, cf. #9

close
