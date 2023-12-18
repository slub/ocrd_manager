#!/bin/bash
# OCR-D task to be run as OCR script step by Kitodo.Presentation
# To be called (after copying METS file) via Manager, e.g.:
#     ssh -Tn -p 9022 ocrd@ocrd-manager process_mets.sh \
#                                       --img-grp ORIGINAL --ocr-grp FULLTEXT \
#                                       --pages PHYS_0010..PHYS_0999 --workflow myocr.sh \
#                                       /home/goobi/work/daten/501543/mets.xml
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
  PAGES=
  IMAGES_GRP=DEFAULT
  RESULT_GRP=FULLTEXT
  URL_PREFIX=
  while (($#)); do
    case "$1" in
      --help|-h) cat <<EOF
SYNOPSIS:

$0 [OPTIONS] METS

where OPTIONS can be any/all of:
 --workflow FILE    workflow file to use for processing, default:
                    $WORKFLOW
 --no-validate      skip comprehensive validation of workflow results
 --pages RANGE      selection of physical page range to process
 --img-grp GRP      fileGrp to read input images from, default:
                    $IMAGES_GRP
 --ocr-grp GRP      fileGrp to write output OCR text to, default:
                    $RESULT_GRP
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
EOF
                 exit;;
      --workflow) WORKFLOW="$2"; shift;;
      --no-validate) VALIDATE=0;;
      --img-grp) IMAGES_GRP="$2"; shift;;
      --ocr-grp) RESULT_GRP="$2"; shift;;
      --pages) PAGES="$2"; shift;;
      --url-prefix) URL_PREFIX="$2"; shift;;
      *) METS_PATH="$1";
         PROCESS_ID=$(ocrd workspace -m "$METS_PATH" get-id)
         PROCESS_DIR=$(dirname "$METS_PATH");
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
WEBHOOK_KEY_DATA="{\"metsPath\" : $METS_PATH}"

# run the workflow script on the Controller non-interactively and log its output locally
# subsequently validate and postprocess the results
# do all this in a subshell in the background, so we can return immediately
(
  init_task

  pre_clone_to_workdir

  pre_sync_workdir

  webhook_send_started

  ocrd_exec ocrd_enter_workdir ocrd_validate_workflow ocrd_process_workflow

  post_sync_workdir

  if ((VALIDATE)); then post_validate_workdir; fi

  post_process_to_mets

  webhook_send_completed

) |& tee -a $WORKDIR/ocrd.log 2>&1 | logger -p user.info -t $TASK &>/dev/null & # without output redirect, ssh will not close the connection upon exit, cf. #9

close
