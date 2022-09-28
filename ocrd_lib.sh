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

parse_args_for_presentation() {
  LANGUAGE=
  SCRIPT=
  PROCESS_ID=
  TASK_ID=
  WORKFLOW=ocr-workflow-default.sh
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
    *for_presentation.sh)
      parse_args_for_presentation "$@";;
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

ocrd_enter_workdir() {
  echo "if test -f '$REMOTEDIR/mets.xml'; then OV=--overwrite; else OV=; fi"
  echo "cd '$REMOTEDIR'"
  echo 'echo $$ > ocrd.pid'
}

ocrd_process_workflow() {
  echo -n 'ocrd process $OV '
  if test -n "${PAGES:-}"; then echo -n "-g $PAGES "; fi
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

pre_clone_to_workdir() {
  # copy the METS and its directory controlled by Kitodo.Presentation
  # to the transient directory controlled by the Manager
  if test -f "$WORKDIR/mets.xml"; then
    # already a workspace - repeated run
    # there is no command for METS synchronization,
    # so just check roughly
    # (also fails if either side is not a valid METS)
    diff -u <(ocrd workspace -m "$METS_PATH" list-page) <(ocrd workspace -d "$WORKDIR" list-page)
  else
    # we cannot use ocrd workspace clone, because it does not offer copying local files
    # (only download all remote or download nothing)
    cp -v "$METS_PATH" "$WORKDIR"/mets.xml
    rsync -T /tmp --exclude=$(basename "$METS_PATH") -av "$(dirname "$METS_PATH")"/ "$WORKDIR"
    # now rename the input file grp to the OCR-D default
    # (cannot use ocrd workspace rename-group due to core#913)
    #ocrd workspace -d "$WORKDIR" rename-group $IMAGES_GRP OCR-D-IMG
    xmlstarlet ed -L -N mods=http://www.loc.gov/mods/v3 -N mets=http://www.loc.gov/METS/ -N xlink=http://www.w3.org/1999/xlink \
               -u "/mets:mets/mets:fileSec/mets:fileGrp[@USE='$IMAGES_GRP']/@USE" -v OCR-D-IMG "$WORKDIR/mets.xml"
    # now remove the output file grp, if it exists
    ocrd workspace -d "$WORKDIR" remove-group -fr $RESULT_GRP
    # workaround for core#485
    ocrd workspace -d "$WORKDIR" remove -f FULLDOWNLOAD
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

post_process_to_mets() {
 # use fileGrp of newest ALTO file as single result
  lastpage=$(ocrd workspace -d "$WORKDIR" \
                  list-page | tail -1)
  ocrgrp=$(ocrd workspace -d "$WORKDIR" \
                find -m "//(application/alto[+]xml|text/xml)" -g ${PAGES:-$lastpage} -k fileGrp | tail -1)
  # extract text result
  mkdir -p "$PROCESS_DIR/$RESULT_GRP"
  while read page path file; do
    # remove any existing files for this page
    ocrd workspace -m "$METS_PATH" remove -f $(ocrd workspace -m "$METS_PATH" find -G $RESULT_GRP -g $page -k ID)
    # copy and reference new file for this page
    cp -v "$WORKDIR/$path" "$PROCESS_DIR/$RESULT_GRP/"
    fname="$(basename "$path")"
    ocrd workspace -m "$METS_PATH" add -C -G $RESULT_GRP -i $file -m application/alto+xml -g $page "$RESULT_GRP/$fname"
  done < <(ocrd workspace -d "$WORKDIR" \
                find -G $ocrgrp -m "//(application/alto[+]xml|text/xml)" -g ${PAGES:-//.*} \
                -k pageId -k local_filename -k ID)
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
