#!/bin/bash
# OCR-D utils for ocr processing

set -eu
set -o pipefail

TASK=$(basename $0)

logerr() {
  logger -p user.info -t $TASK "terminating with error \$?=$? from ${BASH_COMMAND} on line $(caller)"
}

parse_args_for_production() {
  LANGUAGE=
  SCRIPT=
  PROCESS_ID=
  TASK_ID=
  WORKFLOW=ocr-workflow-default.sh
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

# initialize variables, create ord-d work directory and exit if something is missing
init() {
  trap logerr ERR

  PID=$$

  cd /data

  logger -p user.info -t $TASK "ocr_init initialize variables and directory structure"
  logger -p user.notice -t $TASK "running with $* CONTROLLER=${CONTROLLER:-} ACTIVEMQ=${ACTIVEMQ:-}"

  case $TASK in
    *for_production.sh)
      parse_args_for_production "$@";;
    *)
      logger -p user.error -t $TASK "unknown scenario $TASK"
      exit 1
  esac

  if ! test -d "$PROCESS_DIR"; then
    logger -p user.error -t $TASK "invalid input directory '$PROCESS_DIR'"
    exit 2
  fi

  WORKFLOW=$(command -v "$WORKFLOW" || realpath "$WORKFLOW")
  if ! test -f "$WORKFLOW"; then
    logger -p user.error -t $TASK "invalid workflow '$WORKFLOW'"
    exit 3
  fi
  logger -p user.notice -t $TASK "using workflow '$WORKFLOW':"
  ocrd_format_workflow | logger -p user.notice -t $TASK

  if test -z "$CONTROLLER" -o "$CONTROLLER" = "${CONTROLLER#*:}"; then
    logger -p user.error -t $TASK "envvar CONTROLLER='$CONTROLLER' must contain host:port"
    exit 4
  fi
  CONTROLLERHOST=${CONTROLLER%:*}
  CONTROLLERPORT=${CONTROLLER#*:}

  WORKDIR=ocr-d/"$PROCESS_DIR" # will use other mount-point than /data soon
  if ! mkdir -p "$WORKDIR"; then
    logger -p user.error -t $TASK "insufficient permissions on /data volume"
    exit 5
  fi
  # try to be unique here (to avoid clashes)
  REMOTEDIR="KitodoJob_${PID}_$(basename $PROCESS_DIR)"

  # create stats for monitor
  mkdir -p /run/lock/ocrd.jobs/
  {
    echo PID=$PID
    echo PROCESS_ID=$PROCESS_ID
    echo TASK_ID=$TASK_ID
    echo PROCESS_DIR=$PROCESS_DIR
    echo WORKDIR=$WORKDIR
    echo REMOTEDIR=$REMOTEDIR
    echo WORKFLOW=$WORKFLOW
    echo CONTROLLER=$CONTROLLER
  } > /run/lock/ocrd.jobs/$REMOTEDIR

}

logret() {
    sed -i 1s/.*/RETVAL=$?/ /run/lock/ocrd.jobs/$REMOTEDIR
}

init_task() {
  trap logret EXIT
}

# parse shell script notation into tasks syntax
ocrd_format_workflow() {
  cat "$WORKFLOW" | sed '/^[ ]*#/d;s/#.*//;s/"/\\"/g;s/^/"/;s/$/"/' | tr '\n\r' '  '
  echo
}

# ocrd import from workdir
ocrd_import_workdir() {
  echo "if test -f '$REMOTEDIR/mets.xml'; then OV=--overwrite; else OV=; ocrd-import -i '$REMOTEDIR'; fi"
  echo "cd '$REMOTEDIR'"
  echo 'echo $$ > ocrd.pid'
}

ocrd_process_workflow() {
  echo -n 'ocrd process $OV '
  ocrd_format_workflow
}

# execute commands via ssh by the controller
ocrd_exec() {
  logger -p user.info -t $TASK "execute $# commands via SSH by the controller"
  {
    echo "set -Ee"
    for param in "$@"; do
      $param
    done
  } | ssh -T -p "${CONTROLLERPORT}" ocrd@${CONTROLLERHOST} 2>&1
}

pre_process_to_workdir() {
  # copy the data from the process directory controlled by Kitodo.Production
  # to the transient directory controlled by the Manager
  # (currently the same share, but will be distinct volumes;
  #  so the admin can decide to either mount distinct shares,
  #  which means the images will have to be physically copied,
  #  or the same share twice, which means zero-cost copying).
  if test -f "$WORKDIR/mets.xml"; then
    # already a workspace - repeated run
    rsync -T /tmp -av "$PROCESS_DIR/$IMAGES_SUBDIR/" "$WORKDIR"
  else
    cp -vr --reflink=auto "$PROCESS_DIR/$IMAGES_SUBDIR" "$WORKDIR"
  fi
}

pre_sync_workdir () {
  # copy the data explicitly from Manager to Controller
  rsync -av -e "ssh -p $CONTROLLERPORT -l ocrd" "$WORKDIR/" $CONTROLLERHOST:/data/$REMOTEDIR
}

ocrd_validate_workflow () {
  echo -n 'ocrd validate tasks $OV --workspace . '
  ocrd_format_workflow
}

post_sync_workdir () {
    # copy the results back from Controller to Manager
    rsync -av -e "ssh -p $CONTROLLERPORT -l ocrd" $CONTROLLERHOST:/data/$REMOTEDIR/ "$WORKDIR"
    # TODO: maybe also schedule cleanup (or have a cron job delete dirs in /data which are older than N days)
    # e.g. `ssh --port $CONTROLLERPORT ocrd@$CONTROLLERHOST rm -fr /data/"$WORKDIR"`
}

post_validate_workdir() {
  ocrd workspace -d "$WORKDIR" validate -s mets_unique_identifier -s mets_file_group_names -s pixel_density
}

post_process_to_procdir() {
  imggrp=OCR-D-IMG
  # use last fileGrp as single result
  ocrgrp=$(ocrd workspace -d "$WORKDIR" list-group | tail -1)
  # map and copy to Kitodo filename conventions
  mkdir -p "$PROCESS_DIR/$RESULT_SUBDIR"
  # use the same basename as the input image
  declare -A page2base
  while read page path; do
    page2base["$page"]="$(basename ${path%.*})"
  done < <(ocrd workspace -d "$WORKDIR" find -G $imggrp -k pageId -k local_filename)
  while read page path; do
    basename="${page2base[$page]}"; extension=${path##*.}
    cp -v "$WORKDIR/$path" "$PROCESS_DIR/$RESULT_SUBDIR/$basename.$extension"
  done < <(ocrd workspace -d "$WORKDIR" find -G $ocrgrp -k pageId -k local_filename)
}

close_task() {
  if test -n "$ACTIVEMQ" -a -n "$ACTIVEMQ_CLIENT" -a -n "$TASK_ID" -a -n "$PROCESS_ID"; then
    java -Dlog4j2.configurationFile=$ACTIVEMQ_CLIENT_LOG4J2 -jar "$ACTIVEMQ_CLIENT" "tcp://$ACTIVEMQ?closeAsync=false" "KitodoProduction.FinalizeStep.Queue" $TASK_ID $PROCESS_ID
  fi
  logret # communicate retval 0
}

# exit in async or sync mode
close() {
  if test -n "$ACTIVEMQ" -a -n "$ACTIVEMQ_CLIENT" -a -n "$TASK_ID" -a -n "$PROCESS_ID"; then
    logger -p user.info -t $TASK "ocr_exit in async mode - immediate termination of the script"
    # prevent any RETVAL from being written yet
    trap - EXIT
    # fail so Kitodo will listen to the actual time the job is done via ActiveMQ
    exit 1
  else
    # become synchronous again
    logger -p user.info -t $TASK "ocr_exit in sync mode - wait until the processing is completed"
    wait $!
    #rm -f /run/lock/ocrd.jobs/$REMOTEDIR
  fi
}
